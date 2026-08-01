module Scoring
  # Keyset-paginated inspection queue.
  #
  # Stability contract: the queue is ordered by (total_score DESC, hazard_point_id
  # ASC). hazard_point_id is immutable, so the sort key of any already-returned
  # row never changes — even while equal-scored rows are being written
  # continuously. Cursor pagination walks strictly past the last (score, id)
  # seen, so pages never overlap and existing rows never jump between pages.
  class Queue
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 1_000

    Page = Data.define(:records, :next_cursor) do
      def to_h
        {
          items: records.map { |r| Scoring::Presenter.queue_item(r) },
          next_cursor: next_cursor
        }
      end
    end

    # policy: the ScoringPolicy whose materialised scores form this queue.
    def initialize(policy:)
      @policy = policy
    end

    # cursor: opaque "<total_score>:<hazard_point_id>" from a prior page.
    def page(limit: DEFAULT_LIMIT, cursor: nil, scheduling_status: nil)
      # Blank/absent limit falls back to the default rather than clamping to 1.
      limit = limit.presence ? limit.to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT

      relation = PriorityScore
        .where(scoring_policy_id: @policy.id)
        .queue_ordered
      relation = relation.where(scheduling_status: scheduling_status) if scheduling_status.present?
      relation = apply_cursor(relation, cursor)

      records = relation.limit(limit + 1).to_a
      next_cursor = nil
      if records.size > limit
        last = records[limit - 1]
        next_cursor = encode_cursor(last)
        records = records.first(limit)
      end

      Page.new(records: records, next_cursor: next_cursor)
    end

    private

    def apply_cursor(relation, cursor)
      return relation if cursor.blank?

      total, hp_id = decode_cursor(cursor)
      # Strictly after (total DESC, hazard_point_id ASC): either a lower score,
      # or the same score with a larger hazard_point_id.
      relation.where(
        "(priority_scores.total_score < :total) OR " \
        "(priority_scores.total_score = :total AND priority_scores.hazard_point_id > :hp)",
        total: total, hp: hp_id
      )
    end

    def encode_cursor(record)
      "#{record.total_score}:#{record.hazard_point_id}"
    end

    def decode_cursor(cursor)
      total, hp_id = cursor.to_s.split(":", 2)
      [Integer(total), Integer(hp_id)]
    rescue ArgumentError, TypeError
      raise ArgumentError, "invalid cursor: #{cursor.inspect}"
    end
  end
end
