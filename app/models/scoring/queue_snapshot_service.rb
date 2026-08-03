module Scoring
  # Creates an immutable, named snapshot of the current inspection queue and
  # provides cursor-based pagination over that frozen snapshot.
  #
  # Why this exists
  # ---------------
  # During a full queue traversal, dispatchers may continue writing new
  # evidence and recomputing scores. A live ORDER BY query would shift items
  # around, causing pages to skip or repeat entries. A QueueSnapshot freezes
  # the ordered list of priority_score IDs at creation time; subsequent pages
  # read from queue_snapshot_items, which never change for the life of the
  # snapshot.
  #
  # Strategy binding
  # ----------------
  # The snapshot is created against a specific scoring strategy (the one
  # effective at snapshot_at by default). The snapshot stores
  # scoring_strategy_id so that even if a new strategy is published later,
  # the snapshot's items remain bound to the original "round" of scoring.
  #
  # Cursor / pagination
  # -------------------
  # The cursor is simply the last seen position (0-based offset into the
  # frozen items list). Because the list never changes, pages are perfectly
  # stable: no items are missed, no items repeat.
  class QueueSnapshotService
    DEFAULT_PAGE_SIZE = 50
    MAX_PAGE_SIZE = 200

    # --- Creation ----------------------------------------------------------

    def self.create(name:, strategy: nil, snapshot_at: Time.current,
                    include_blocked: true, risk_level: nil,
                    dispatch_status: nil)
      new(name: name, strategy: strategy, snapshot_at: snapshot_at,
          include_blocked: include_blocked, risk_level: risk_level,
          dispatch_status: dispatch_status).create
    end

    def initialize(name:, strategy:, snapshot_at:, include_blocked:,
                   risk_level:, dispatch_status:)
      @name = name
      @strategy = strategy
      @snapshot_at = snapshot_at
      @include_blocked = include_blocked
      @risk_level = risk_level
      @dispatch_status = dispatch_status
    end

    def create
      resolved = @strategy || StrategySelector.for_time(@snapshot_at)

      QueueSnapshot.transaction do
        snapshot = QueueSnapshot.create!(
          name: @name,
          scoring_strategy: resolved,
          snapshot_at: @snapshot_at,
          include_blocked: @include_blocked,
          risk_level_filter: @risk_level,
          dispatch_status_filter: @dispatch_status,
          filters_json: {
            include_blocked: @include_blocked,
            risk_level: @risk_level,
            dispatch_status: @dispatch_status
          }
        )

        scores = fetch_current_scores(resolved)
        rows = scores.each_with_index.map do |score, idx|
          {
            queue_snapshot_id: snapshot.id,
            priority_score_id: score.id,
            hazard_point_id: score.hazard_point_id,
            position: idx,
            total_score: score.total_score,
            risk_level: score.risk_level,
            dispatch_status: score.dispatch_status,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        QueueSnapshotItem.insert_all(rows) if rows.any?
        snapshot.update!(total_count: rows.size)
        snapshot
      end
    end

    # --- Reading -----------------------------------------------------------

    def self.page(snapshot, cursor: nil, per_page: DEFAULT_PAGE_SIZE)
      Reader.new(snapshot).page(cursor: cursor, per_page: per_page)
    end

    # Paginates over a frozen QueueSnapshot.
    class Reader
      def initialize(snapshot)
        @snapshot = snapshot
      end

      def page(cursor: nil, per_page: DEFAULT_PAGE_SIZE)
        page_size = clamp(per_page)
        after_position = cursor.nil? ? -1 : cursor.to_i

        items = @snapshot.items
                     .ordered
                     .includes(:hazard_point, priority_score: %i[evidence_snapshot scoring_strategy])
                     .where("position > ?", after_position)
                     .limit(page_size + 1)
                     .to_a

        has_more = items.size > page_size
        items = items.first(page_size)

        next_cursor = has_more ? items.last.position.to_s : nil

        {
          snapshot: @snapshot,
          items: items,
          total: @snapshot.total_count,
          per_page: page_size,
          next_cursor: next_cursor,
          has_more: has_more
        }
      end

      private

      def clamp(value)
        i = value.to_i
        i = DEFAULT_PAGE_SIZE if i <= 0
        [i, MAX_PAGE_SIZE].min
      end
    end

    private

    # Fetches the live, ordered set of CURRENT priority scores that should be
    # frozen into the snapshot. The ordering matches QueueService:
    # total_score DESC, hazard_point_id ASC.
    def fetch_current_scores(strategy)
      scope = PriorityScore
              .current
              .joins("INNER JOIN (#{Scoring::QueueService.latest_snapshot_sql}) AS latest_snap
                      ON latest_snap.id = priority_scores.evidence_snapshot_id")
              .where(scoring_strategy_id: strategy.id)
              .includes(:hazard_point)
              .order(Arel.sql("priority_scores.total_score DESC, priority_scores.hazard_point_id ASC"))

      scope = scope.where(dispatch_status: @dispatch_status) if @dispatch_status.present?
      scope = scope.where(risk_level: @risk_level) if @risk_level.present?
      scope = scope.where(dispatch_status: "available") unless @include_blocked
      scope.to_a
    end
  end
end
