# frozen_string_literal: true

# Keyset-paginated read model over the inspection queue.
#
# Two modes:
#   * live (snapshot: nil) — reads the current score of every hazard point;
#   * pinned (snapshot given) — reads only the members materialized into
#     that QueueSnapshot at capture time, insulated from later writes.
#
# Ordering is (total_score DESC, id ASC). The cursor encodes the last seen
# (total_score, id) pair, so within a mode the page order cannot jump back
# and forth even under continuous writes with identical scores — and in
# pinned mode the membership itself is fixed.
class InspectionQueue
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 500

  Entry = Data.define(:records, :next_cursor)

  def self.call(limit: DEFAULT_LIMIT, cursor: nil, scheduling_status: nil, snapshot: nil)
    limit = limit.to_i
    limit = DEFAULT_LIMIT if limit <= 0
    limit = [limit, MAX_LIMIT].min

    scope = base_scope(snapshot)
    scope = scope.where(scheduling_status: scheduling_status) if scheduling_status.present?

    if cursor.present?
      last_score, last_id = decode_cursor(cursor)
      scope = scope.where(
        'score_records.total_score < :s OR (score_records.total_score = :s AND score_records.id > :i)',
        s: last_score, i: last_id
      )
    end

    records = scope.limit(limit + 1).to_a
    has_more = records.size > limit
    records = records.first(limit)
    next_cursor = has_more ? encode_cursor(records.last) : nil

    Entry.new(records: records, next_cursor: next_cursor)
  end

  def self.base_scope(snapshot)
    scope = ScoreRecord.queue_order.includes(:hazard_point, :evidence_snapshot, :strategy_version)
    return scope.current if snapshot.nil?

    scope.joins(:queue_snapshot_entries)
         .where(queue_snapshot_entries: { queue_snapshot_id: snapshot.id })
  end
  private_class_method :base_scope

  def self.encode_cursor(record)
    Base64.urlsafe_encode64({ "s" => record.total_score, "i" => record.id }.to_json)
  end

  def self.decode_cursor(cursor)
    data = JSON.parse(Base64.urlsafe_decode64(cursor))
    [Integer(data.fetch("s")), Integer(data.fetch("i"))]
  rescue JSON::ParserError, ArgumentError, KeyError, TypeError
    raise ActionController::BadRequest, "invalid cursor"
  end
end
