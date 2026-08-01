require "digest"

# An immutable record of the evidence facts for one hazard point at one instant.
#
# Immutability is a hard rule: once created, a snapshot never changes. This lets
# any scoring policy version be replayed against a historical snapshot and get
# byte-identical inputs. The callbacks here enforce *immutability only* — they
# contain no scoring rules (those live in Scoring::Engine).
class EvidenceSnapshot < ApplicationRecord
  belongs_to :hazard_point
  has_many :priority_scores, dependent: :destroy

  # Fields that define the frozen evidence. Any change to these would
  # invalidate historical replays, so they are locked after creation.
  FROZEN_ATTRS = %w[
    hazard_point_id captured_at rainfall_mm_24h historical_event_count
    road_accessible point_last_inspected_at content_digest
  ].freeze

  validates :captured_at, presence: true
  validates :rainfall_mm_24h,
            numericality: { greater_than_or_equal_to: 0 }
  validates :historical_event_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :road_accessible, inclusion: { in: [true, false] }

  before_validation :assign_content_digest, on: :create
  before_update :reject_mutation
  before_destroy :reject_deletion

  def road_accessible?
    road_accessible
  end

  # Idempotent capture keyed by an optional caller-supplied business_key:
  #   * no business_key                 -> always creates a new snapshot
  #   * business_key, first time        -> creates the snapshot
  #   * business_key, same payload      -> returns the existing snapshot (idempotent)
  #   * business_key, different payload -> raises ConflictingBusinessKeyError
  # Payload equivalence is decided by the content_digest of the frozen facts, so
  # the check is exact and immune to attribute ordering.
  def self.capture!(hazard_point:, business_key: nil, **facts)
    incoming = new(hazard_point: hazard_point, business_key: business_key, **facts)

    if business_key.blank?
      incoming.save!
      return incoming
    end

    existing = find_by(business_key: business_key)
    if existing
      # Recompute the incoming digest to compare payloads without persisting.
      incoming.send(:assign_content_digest)
      return existing if existing.content_digest == incoming.content_digest

      raise Scoring::ConflictingBusinessKeyError.new(business_key)
    end

    # Insert inside a savepoint so a lost unique-key race only rolls back this
    # statement, leaving any surrounding transaction usable for the re-resolve.
    begin
      transaction(requires_new: true) { incoming.save! }
      incoming
    rescue ActiveRecord::RecordNotUnique
      winner = find_by!(business_key: business_key)
      incoming.send(:assign_content_digest)
      return winner if winner.content_digest == incoming.content_digest

      raise Scoring::ConflictingBusinessKeyError.new(business_key)
    end
  end

  # Deterministic fingerprint of the frozen facts. Recomputable during tests to
  # prove the stored snapshot was never altered.
  def self.digest_for(attrs)
    material = [
      attrs[:hazard_point_id],
      attrs[:captured_at].respond_to?(:iso8601) ? attrs[:captured_at].utc.iso8601(6) : attrs[:captured_at],
      BigDecimal(attrs[:rainfall_mm_24h].to_s).to_s("F"),
      attrs[:historical_event_count].to_i,
      attrs[:road_accessible] ? "1" : "0",
      attrs[:point_last_inspected_at].respond_to?(:iso8601) ? attrs[:point_last_inspected_at].utc.iso8601(6) : attrs[:point_last_inspected_at]
    ].join("|")
    Digest::SHA256.hexdigest(material)
  end

  private

  def assign_content_digest
    self.content_digest = self.class.digest_for(
      hazard_point_id: hazard_point_id,
      captured_at: captured_at,
      rainfall_mm_24h: rainfall_mm_24h,
      historical_event_count: historical_event_count,
      road_accessible: road_accessible,
      point_last_inspected_at: point_last_inspected_at
    )
  end

  def reject_mutation
    if (FROZEN_ATTRS & changed).any?
      raise ActiveRecord::RecordNotSaved.new("evidence snapshots are immutable", self)
    end
  end

  def reject_deletion
    throw(:abort)
  end
end
