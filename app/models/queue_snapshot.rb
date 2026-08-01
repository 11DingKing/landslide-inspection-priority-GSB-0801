# frozen_string_literal: true

# An immutable, named read snapshot of the inspection queue.
#
# Capturing pins two things:
#   * the strategy round — the published strategy version applicable at
#     capture time (e.g. round 2 == v2), stored on the snapshot;
#   * the membership — exactly the score records that were current,
#     materialized in queue_snapshot_entries.
#
# Because entries reference the immutable score records directly, a cursor
# traversal over the snapshot is fully insulated from later recomputations
# that move the live is_current pointer: no skipped entries, no duplicates.
class QueueSnapshot < ApplicationRecord
  belongs_to :strategy_version
  has_many :queue_snapshot_entries, dependent: :destroy
  has_many :score_records, through: :queue_snapshot_entries

  validates :name, presence: true, uniqueness: true

  def self.capture!(name:, at: Time.current)
    strategy = StrategyVersion.applicable_to(at)
    raise PriorityCalculator::NoApplicableStrategy,
          "no published strategy covers #{at.iso8601}" if strategy.nil?

    transaction do
      create!(name: name, strategy_version: strategy).tap do |snapshot|
        ids = ScoreRecord.current.queue_order.pluck(:id)
        rows = ids.map { |rid| { queue_snapshot_id: snapshot.id, score_record_id: rid } }
        QueueSnapshotEntry.insert_all(rows) if rows.any?
      end
    end
  end

  def entry_count
    queue_snapshot_entries.count
  end
end
