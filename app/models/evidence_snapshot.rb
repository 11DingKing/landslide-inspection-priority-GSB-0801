# frozen_string_literal: true

# Immutable by construction: the database trigger
# (see CreateEvidenceSnapshots) rejects every UPDATE/DELETE, and the model
# additionally refuses to persist changes to a persisted snapshot so callers
# get a validation error instead of a database exception.
class EvidenceSnapshot < ApplicationRecord
  belongs_to :hazard_point
  has_many :score_records, dependent: :restrict_with_error

  validates :rainfall_24h_mm, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than: 10_000 }
  validates :historical_event_count, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :captured_at, presence: true
  validates :road_accessible, inclusion: { in: [true, false] }
  validates :client_reference, uniqueness: true, allow_nil: true
  validate :immutable_attributes_unchanged, on: :update

  def readonly?
    persisted?
  end

  # Normalized comparison used for idempotent resubmission: does +attrs+
  # describe exactly the evidence this snapshot already holds?
  def same_evidence?(attrs)
    attrs = attrs.to_h.deep_symbolize_keys
    rainfall_24h_mm == BigDecimal(attrs[:rainfall_24h_mm].to_s) &&
      historical_event_count == Integer(attrs[:historical_event_count]) &&
      road_accessible == ActiveModel::Type::Boolean.new.cast(attrs[:road_accessible]) &&
      time_equal?(last_inspected_at, attrs[:last_inspected_at]) &&
      time_equal?(captured_at, attrs[:captured_at])
  end

  def evidence
    {
      rainfall_24h_mm: rainfall_24h_mm,
      historical_event_count: historical_event_count,
      last_inspected_at: last_inspected_at,
      road_accessible: road_accessible,
      captured_at: captured_at
    }
  end

  private

  def time_equal?(stored, incoming)
    return stored.nil? if incoming.nil? || incoming == ""

    stored == Time.zone.parse(incoming.to_s)
  end

  def immutable_attributes_unchanged
    errors.add(:base, "evidence snapshots are immutable") if changed.any?
  end
end
