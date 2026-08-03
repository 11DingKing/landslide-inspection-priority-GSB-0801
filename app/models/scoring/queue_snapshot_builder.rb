module Scoring
  class QueueSnapshotBuilder
    class << self
      def build!(snapshot_key:, filters: {}, now: Time.current)
        new(snapshot_key, filters: filters, now: now).build!
      end
    end

    def initialize(snapshot_key, filters:, now:)
      @snapshot_key = snapshot_key
      @filters = filters || {}
      @now = now
    end

    def build!
      existing = QueueReadSnapshot.find_by(snapshot_key: @snapshot_key)
      return existing if existing

      baseline = StrategySelector.for_time(@now)

      ApplicationRecord.transaction do
        snapshot = QueueReadSnapshot.create!(
          snapshot_key: @snapshot_key,
          frozen_at: @now,
          strategy_baseline_id: baseline.id,
          filters: @filters,
          total_entries: 0
        )

        rows = QueueService.new(@filters.stringify_keys).current_scope_all
        bulk_insert_entries(snapshot, rows)
        snapshot.update!(total_entries: rows.size)
        snapshot
      end
    rescue ActiveRecord::RecordNotUnique
      QueueReadSnapshot.find_by!(snapshot_key: @snapshot_key)
    end

    private

    def bulk_insert_entries(snapshot, rows)
      now = Time.current
      entries = rows.each_with_index.map do |score, idx|
        {
          queue_read_snapshot_id: snapshot.id,
          priority_score_id: score.id,
          hazard_point_id: score.hazard_point_id,
          position: idx + 1,
          total_score: score.total_score,
          risk_level: score.risk_level,
          dispatch_status: score.dispatch_status,
          created_at: now,
          updated_at: now
        }
      end
      return if entries.empty?

      QueueReadSnapshotEntry.insert_all!(entries)
    end
  end
end
