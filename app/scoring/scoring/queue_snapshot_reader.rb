module Scoring
  # Paginates a queue-read snapshot's frozen items. Uses the same keyset cursor
  # semantics as the live Queue — (total_score DESC, hazard_point_id ASC) with an
  # opaque "<total_score>:<hazard_point_id>" cursor — but reads ONLY the frozen
  # items. Because the frozen keys never change, resuming the original cursor
  # after concurrent recomputes yields the remaining items with no misses and no
  # duplicates.
  class QueueSnapshotReader
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 1_000

    Page = Data.define(:records, :next_cursor) do
      def to_h
        {
          items: records.map { |r| Scoring::Presenter.frozen_queue_item(r) },
          next_cursor: next_cursor
        }
      end
    end

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def page(limit: DEFAULT_LIMIT, cursor: nil)
      limit = limit.presence ? limit.to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT

      relation = @snapshot.items.keyset_ordered
      relation = apply_cursor(relation, cursor)

      records = relation.limit(limit + 1).to_a
      next_cursor = nil
      if records.size > limit
        next_cursor = encode_cursor(records[limit - 1])
        records = records.first(limit)
      end

      Page.new(records: records, next_cursor: next_cursor)
    end

    private

    def apply_cursor(relation, cursor)
      return relation if cursor.blank?

      total, hp_id = decode_cursor(cursor)
      relation.where(
        "(queue_snapshot_items.total_score < :total) OR " \
        "(queue_snapshot_items.total_score = :total AND queue_snapshot_items.hazard_point_id > :hp)",
        total: total, hp: hp_id
      )
    end

    def encode_cursor(item)
      "#{item.total_score}:#{item.hazard_point_id}"
    end

    def decode_cursor(cursor)
      total, hp_id = cursor.to_s.split(":", 2)
      [Integer(total), Integer(hp_id)]
    rescue ArgumentError, TypeError
      raise ArgumentError, "invalid cursor: #{cursor.inspect}"
    end
  end
end
