# A named, immutable, frozen copy of one policy's `current` ranking, captured at
# build time. Traversals pinned to a snapshot are stable: they read only the
# frozen items, so concurrent recomputes that move `current` scores never cause
# missed or duplicated rows. Building a NEW snapshot is how you observe updates.
class QueueSnapshot < ApplicationRecord
  belongs_to :scoring_policy
  has_many :items, class_name: "QueueSnapshotItem", dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :built_at, presence: true

  before_update :reject_mutation
  before_destroy :reject_deletion

  private

  # Frozen after creation: the whole point is stability across a traversal.
  def reject_mutation
    raise ActiveRecord::RecordNotSaved.new("queue snapshots are immutable", self)
  end

  def reject_deletion
    throw(:abort)
  end
end
