class QueueSnapshotsController < ApplicationController
  before_action :set_snapshot, only: %i[show items]

  # GET /queue_snapshots
  def index
    snapshots = QueueSnapshot.ordered.limit(100)
    render json: snapshots
  end

  # GET /queue_snapshots/:id
  def show
    render json: serialize_snapshot(@snapshot, items: [])
  end

  # POST /queue_snapshots
  #
  # Creates a new immutable queue snapshot. The queue is frozen at the
  # moment of creation; subsequent score recomputations do not affect it.
  #
  # Params:
  #   name             – required, e.g. "queue-20260802-01"
  #   strategy_id      – optional; defaults to the strategy effective now
  #   snapshot_at      – optional; defaults to Time.current
  #   include_blocked  – optional; default true
  #   risk_level       – optional filter
  #   dispatch_status  – optional filter
  def create
    snapshot = Scoring::QueueSnapshotService.create(
      name: params.require(:name),
      strategy: strategy_override,
      snapshot_at: parse_time(params[:snapshot_at]) || Time.current,
      include_blocked: boolean_param(:include_blocked, true),
      risk_level: params[:risk_level],
      dispatch_status: params[:dispatch_status]
    )
    render json: serialize_snapshot(snapshot, items: []), status: :created
  end

  # GET /queue_snapshots/:id/items?cursor=&per_page=
  #
  # Returns one page of the frozen snapshot. The cursor is an opaque position
  # token; pass the next_cursor from each response to get the next page.
  def items
    result = Scoring::QueueSnapshotService.page(
      @snapshot,
      cursor: params[:cursor],
      per_page: params[:per_page]
    )
    render json: {
      snapshot: {
        id: @snapshot.id,
        name: @snapshot.name,
        snapshot_at: @snapshot.snapshot_at.iso8601,
        strategy_id: @snapshot.scoring_strategy_id,
        version_code: @snapshot.scoring_strategy.version_code,
        total_count: @snapshot.total_count
      },
      items: result[:items].map { |i| serialize_item(i) },
      total: result[:total],
      per_page: result[:per_page],
      next_cursor: result[:next_cursor],
      has_more: result[:has_more]
    }
  end

  private

  def set_snapshot
    @snapshot = QueueSnapshot.find(params[:id])
  end

  def strategy_override
    return nil unless params[:strategy_id].present?

    ScoringStrategy.find(params[:strategy_id])
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  end

  def boolean_param(key, default)
    return default unless params.key?(key)

    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def serialize_snapshot(snapshot, items:)
    {
      id: snapshot.id,
      name: snapshot.name,
      snapshot_at: snapshot.snapshot_at.iso8601,
      strategy_id: snapshot.scoring_strategy_id,
      version_code: snapshot.scoring_strategy.version_code,
      total_count: snapshot.total_count,
      include_blocked: snapshot.include_blocked,
      filters: snapshot.filters_json,
      created_at: snapshot.created_at.iso8601
    }
  end

  def serialize_item(item)
    ps = item.priority_score
    {
      position: item.position,
      priority_score_id: ps.id,
      hazard_point_id: item.hazard_point_id,
      total_score: item.total_score,
      risk_level: item.risk_level,
      dispatch_status: item.dispatch_status,
      version_code: ps.explanation&.dig("version_code"),
      snapshot_time: ps.snapshot_time.iso8601,
      components: ps.components,
      hazard_point: {
        id: item.hazard_point.id,
        name: item.hazard_point.name,
        kind: item.hazard_point.kind,
        external_code: item.hazard_point.external_code
      }
    }
  end
end
