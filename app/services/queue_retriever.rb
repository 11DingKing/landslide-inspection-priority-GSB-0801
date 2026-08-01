class QueueRetriever
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 200

  Page = Struct.new(:items, :next_cursor, :total_count, keyword_init: true)

  def self.call(**options)
    new.call(**options)
  end

  def call(limit: DEFAULT_LIMIT, cursor: nil, dispatch_status: nil,
           include_blocked: true, strategy_version: nil)
    limit = normalize_limit(limit)
    scope = latest_snapshots_scope(strategy_version)
    scope = apply_dispatch_filter(scope, dispatch_status, include_blocked)
    scope = apply_cursor(scope, cursor)

    items = scope.limit(limit + 1).to_a
    has_more = items.size > limit
    items = items.first(limit)

    next_cursor = has_more ? encode_cursor(items.last) : nil

    Page.new(
      items: items,
      next_cursor: next_cursor,
      total_count: count_scope(dispatch_status, include_blocked, strategy_version)
    )
  end

  private

  def normalize_limit(limit)
    value = limit.to_i
    value = DEFAULT_LIMIT if value <= 0
    [value, MAX_LIMIT].min
  end

  def latest_snapshots_scope(strategy_version)
    base = EvidenceSnapshot.all
    if strategy_version
      base = base.joins(:scoring_strategy)
                 .where(scoring_strategies: { version: strategy_version,
                                              status: "published" })
    end

    latest = base
      .select("DISTINCT ON (evidence_snapshots.hazard_point_id) evidence_snapshots.*")
      .order("evidence_snapshots.hazard_point_id, evidence_snapshots.snapshot_at DESC, evidence_snapshots.id DESC")

    EvidenceSnapshot
      .from("(#{latest.to_sql}) AS evidence_snapshots")
      .preload(:hazard_point, :scoring_strategy)
      .order(Arel.sql("evidence_snapshots.total_score DESC, evidence_snapshots.id ASC"))
  end

  def apply_dispatch_filter(scope, dispatch_status, include_blocked)
    if dispatch_status.present?
      scope.where(evidence_snapshots: { dispatch_status: dispatch_status })
    elsif !include_blocked
      scope.where(evidence_snapshots: { dispatch_status: "schedulable" })
    else
      scope
    end
  end

  def apply_cursor(scope, cursor)
    return scope if cursor.blank?

    score, id = decode_cursor(cursor)
    where_clause = <<~SQL
      (evidence_snapshots.total_score < :score)
      OR (evidence_snapshots.total_score = :score AND evidence_snapshots.id > :id)
    SQL
    scope.where(where_clause, score: score.to_i, id: id.to_i)
  end

  def count_scope(dispatch_status, include_blocked, strategy_version)
    scope = latest_snapshots_scope(strategy_version)
    apply_dispatch_filter(scope, dispatch_status, include_blocked).count
  end

  def encode_cursor(item)
    Base64.urlsafe_encode64("#{item.total_score}:#{item.id}")
  end

  def decode_cursor(cursor)
    decoded = Base64.urlsafe_decode64(cursor.to_s)
    score, id = decoded.split(":")
    [score, id]
  rescue ArgumentError
    raise QueueRetriever::Error, "invalid cursor"
  end
end

class QueueRetriever::Error < StandardError; end
