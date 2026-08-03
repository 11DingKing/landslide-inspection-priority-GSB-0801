# A frozen entry in a queue-read snapshot. Copies the ordering keys and display
# fields from the priority score at build time and pins priority_score_id, so
# the explanation still replays against the original v1/v2 policy boundary even
# after later `current` movement. Immutable.
class QueueSnapshotItem < ApplicationRecord
  belongs_to :queue_snapshot
  belongs_to :priority_score
  belongs_to :hazard_point

  # Same stable ordering as the live queue: highest priority first, ties broken
  # by the immutable hazard_point_id.
  scope :keyset_ordered, -> { order(total_score: :desc, hazard_point_id: :asc) }

  before_update :reject_mutation
  before_destroy :allow_cascade_destroy

  private

  def reject_mutation
    raise ActiveRecord::RecordNotSaved.new("queue snapshot items are immutable", self)
  end

  # Items only disappear when their snapshot is torn down (which itself is
  # blocked in normal operation); never individually mutated.
  def allow_cascade_destroy
    true
  end
end
