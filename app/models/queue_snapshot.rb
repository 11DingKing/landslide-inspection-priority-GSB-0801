class QueueSnapshot < ApplicationRecord
  belongs_to :scoring_strategy
  has_many :items,
           class_name: "QueueSnapshotItem",
           foreign_key: :queue_snapshot_id,
           dependent: :destroy,
           inverse_of: :queue_snapshot

  validates :name, presence: true, uniqueness: true
  validates :snapshot_at, presence: true
  validates :total_count, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(snapshot_at: :desc, id: :desc) }
end
