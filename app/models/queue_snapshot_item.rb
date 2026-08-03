class QueueSnapshotItem < ApplicationRecord
  belongs_to :queue_snapshot, inverse_of: :items
  belongs_to :priority_score
  belongs_to :hazard_point

  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_score, presence: true
  validates :risk_level, presence: true
  validates :dispatch_status, presence: true

  scope :ordered, -> { order(:position) }
end
