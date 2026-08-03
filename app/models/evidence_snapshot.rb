class EvidenceSnapshot < ApplicationRecord
  # Fields that define the "payload" for business-key idempotency. If two
  # requests carry the same business_key but differ in any of these fields,
  # the second request is rejected (409). If they match exactly, the existing
  # snapshot is returned (200) instead of creating a duplicate.
  PAYLOAD_FIELDS = %w[
    rainfall_24h_mm
    historical_event_count
    last_inspected_at
    road_accessible
    source_note
  ].freeze

  belongs_to :hazard_point
  has_many :priority_scores, dependent: :restrict_with_error

  validates :snapshot_time, presence: true
  validates :rainfall_24h_mm,
            numericality: { greater_than_or_equal_to: 0, allow_nil: false }
  validates :historical_event_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :business_key, uniqueness: { allow_nil: true, case_sensitive: true }

  before_create :capture_road_status
  before_update :prevent_immutable_changes, if: :immutable_changes_blocked?

  scope :latest_per_point, lambda {
    where(
      <<~SQL
        NOT EXISTS (
          SELECT 1 FROM evidence_snapshots later
          WHERE later.hazard_point_id = evidence_snapshots.hazard_point_id
            AND later.snapshot_time > evidence_snapshots.snapshot_time
        )
      SQL
    )
  }

  scope :ordered_for_queue, -> { order(snapshot_time: :desc, id: :desc) }

  def lock!
    return self if immutable?

    update_column(:immutable, true)
    self
  end

  # Returns a canonical hash of the payload fields used for idempotency /
  # conflict detection. Values are read after type casting so that a Float
  # vs BigDecimal or a nil vs explicit-false comparison does not produce
  # false conflicts.
  def payload_signature
    PAYLOAD_FIELDS.each_with_object({}) do |field, h|
      h[field] = self[field].to_s
    end
  end

  def same_payload_as?(other)
    other_sig = other.respond_to?(:payload_signature) ? other.payload_signature : signature_for(other)
    payload_signature == other_sig
  end

  # Build a signature from an unsaved record (after it has been type-cast).
  def signature_for(candidate)
    EvidenceSnapshot::PAYLOAD_FIELDS.each_with_object({}) do |field, h|
      h[field] = candidate[field].to_s
    end
  end

  private

  def capture_road_status
    return unless has_attribute?(:road_accessible) && self[:road_accessible].nil?

    self.road_accessible = hazard_point.road_accessible
  end

  # The record is mutable until lock! sets immutable=true. The update that
  # flips immutable to true must still go through; only subsequent edits to
  # an already-locked snapshot are rejected.
  def immutable_changes_blocked?
    immutable_was && will_save_change_to_attribute?(:immutable) == false
  end

  def prevent_immutable_changes
    errors.add(:base, "immutable evidence snapshots cannot be modified")
    throw :abort
  end
end
