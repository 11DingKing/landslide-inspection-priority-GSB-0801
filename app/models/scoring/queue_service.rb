module Scoring
  # Retrieves the current inspection queue: for every hazard point, the
  # latest evidence snapshot scored against the strategy that was effective
  # at the snapshot's time (or an explicit strategy when replaying).
  #
  # Stable ordering
  # ---------------
  # ORDER BY total_score DESC, hazard_point_id ASC is deterministic even
  # when hundreds of points share the same total_score. hazard_point_id is
  # a monotonically increasing primary key, so newly inserted points always
  # land AFTER existing ones at the same score and pages do not shuffle
  # under concurrent writes.
  #
  # Pagination
  # ----------
  # Two modes are supported:
  #   * offset/limit (simple, page numbers)
  #   * keyset cursor (recommended for large / continuously-written queues)
  class QueueService
    DEFAULT_PAGE_SIZE = 50
    MAX_PAGE_SIZE = 200

    attr_reader :relation

    def self.list(params = {})
      new(params).list
    end

    def initialize(params = {})
      @params = params
      @only_dispatch = params[:dispatch_status]
      @risk_level = params[:risk_level]
      @include_blocked =
        if params.key?(:include_blocked)
          ActiveModel::Type::Boolean.new.cast(params[:include_blocked])
        else
          true
        end
      @include_blocked = true if @include_blocked.nil?
      @page_size = clamp_page_size(params[:per_page] || params[:limit] || DEFAULT_PAGE_SIZE)
      @offset = (params[:offset] || ((params[:page].to_i).positive? ? (params[:page].to_i - 1) * @page_size : 0)).to_i
      @offset = 0 if @offset.negative?
      @cursor = parse_cursor(params[:cursor])
      @strategy_id = params[:strategy_id]
    end

    def list
      scope = build_relation
      total = scope.unscope(:includes, :order, :select).count
      records = scope.limit(@page_size + 1).to_a

      next_cursor = nil
      if records.size > @page_size
        records = records.first(@page_size)
        last = records.last
        next_cursor = encode_cursor(last.total_score, last.hazard_point_id)
      end

      {
        items: records,
        total: total,
        per_page: @page_size,
        offset: @offset,
        next_cursor: next_cursor,
        has_more: !next_cursor.nil?
      }
    end

    private

    def build_relation
      scope = PriorityScore
              .current
              .joins("INNER JOIN (#{self.class.latest_snapshot_sql}) AS latest_snap
                      ON latest_snap.id = priority_scores.evidence_snapshot_id")
              .includes(:hazard_point, :evidence_snapshot, :scoring_strategy)
              .order(Arel.sql("priority_scores.total_score DESC, priority_scores.hazard_point_id ASC"))

      # When a strategy_id is given, restrict to replay view (scores produced
      # by that strategy). By default the queue shows current scores, which are
      # already bound to the strategy effective at each snapshot's time.
      scope = scope.where(priority_scores: { scoring_strategy_id: @strategy_id }) if @strategy_id
      scope.yield_self { |s| apply_filters(s) }
           .yield_self { |s| apply_pagination(s) }
    end

    def apply_filters(scope)
      scope = scope.where(priority_scores: { dispatch_status: @only_dispatch }) if @only_dispatch.present?
      scope = scope.where(priority_scores: { risk_level: @risk_level }) if @risk_level.present?
      scope = scope.where(priority_scores: { dispatch_status: "available" }) unless @include_blocked
      scope
    end

    def apply_pagination(scope)
      if @cursor
        score, point_id = @cursor
        scope = scope.where(
          "priority_scores.total_score < :s OR " \
          "(priority_scores.total_score = :s AND priority_scores.hazard_point_id > :p)",
          s: score, p: point_id
        )
      else
        scope = scope.offset(@offset)
      end
      scope
    end

    # The most recent evidence_snapshots row per hazard_point. PostgreSQL's
    # DISTINCT ON picks exactly one row per point; we break ties on
    # snapshot_time DESC, then id DESC so the result is fully deterministic.
    #
    # Exposed as a class-level helper because other services (e.g. bulk
    # score computation) need the same "latest per point" row set.
    def self.latest_snapshot_sql
      "SELECT DISTINCT ON (hazard_point_id) id " \
      "FROM evidence_snapshots " \
      "ORDER BY hazard_point_id, snapshot_time DESC, id DESC"
    end

    def clamp_page_size(value)
      i = value.to_i
      i = DEFAULT_PAGE_SIZE if i <= 0
      [i, MAX_PAGE_SIZE].min
    end

    def parse_cursor(raw)
      return nil if raw.blank?

      decoded = Base64.urlsafe_decode64(raw.to_s)
      score, point_id = decoded.split(":", 2)
      [score.to_i, point_id.to_i]
    rescue ArgumentError
      nil
    end

    def encode_cursor(score, point_id)
      Base64.urlsafe_encode64("#{score}:#{point_id}")
    end
  end
end
