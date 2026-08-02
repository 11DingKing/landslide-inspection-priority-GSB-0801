class EvidenceSnapshot < ApplicationRecord
  belongs_to :hazard_point
  has_many :priority_scores, dependent: :restrict_with_error

  validates :snapshot_time, presence: true
  validates :rainfall_24h_mm,
            numericality: { greater_than_or_equal_to: 0, allow_nil: false }
  validates :historical_event_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

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

  private

  def capture_road_status
    self.road_accessible = hazard_point.road_accessible if road_accessible.nil?
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
