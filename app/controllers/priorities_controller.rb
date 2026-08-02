class PrioritiesController < ApplicationController
  # POST /hazard_points/:hazard_point_id/evidence_snapshots/:id/priority
  # Optional params:
  #   strategy_id   – replay with a specific strategy version
  #   as_of         – strategy effective-time override (ISO8601)
  def calculate
    snapshot = EvidenceSnapshot.find(params[:id])
    strategy = find_strategy
    as_of = params[:as_of].present? ? Time.zone.parse(params[:as_of]) : nil

    score = Scoring::PriorityComputer.call(
      snapshot,
      strategy: strategy,
      as_of: as_of,
      now: Time.current
    )

    snapshot.lock!
    render json: serialize_score(score), status: :created
  end

  # GET /priority/queue
  # Query params:
  #   page, per_page, offset, cursor, include_blocked, dispatch_status,
  #   risk_level, strategy_id
  def queue
    result = Scoring::QueueService.list(
      page: params[:page],
      per_page: params[:per_page],
      offset: params[:offset],
      cursor: params[:cursor],
      include_blocked: params[:include_blocked],
      dispatch_status: params[:dispatch_status],
      risk_level: params[:risk_level],
      strategy_id: params[:strategy_id]
    )

    render json: {
      items: result[:items].map { |s| serialize_score(s) },
      total: result[:total],
      per_page: result[:per_page],
      offset: result[:offset],
      next_cursor: result[:next_cursor],
      has_more: result[:has_more]
    }
  end

  # GET /priority/:id/explain – returns the frozen component breakdown and
  # rule version for an already-computed PriorityScore.
  def explain
    score = PriorityScore.find(params[:id])
    component_sum = score.components.sum { |c| c["score"].to_i }

    render json: {
      priority_score_id: score.id,
      hazard_point_id: score.hazard_point_id,
      evidence_snapshot_id: score.evidence_snapshot_id,
      strategy_id: score.scoring_strategy_id,
      version_code: score.explanation.fetch("version_code"),
      strategy_name: score.explanation.fetch("strategy_name"),
      effective_at: score.explanation.fetch("effective_at"),
      snapshot_time: score.explanation.fetch("snapshot_time"),
      computed_at: score.explanation.fetch("computed_at"),
      total_score: score.total_score,
      component_sum: component_sum,
      sum_matches_total: component_sum == score.total_score,
      risk_level: score.risk_level,
      dispatch_status: score.dispatch_status,
      road_accessible: score.road_accessible,
      components: score.components,
      notes: score.explanation.fetch("notes")
    }
  end

  # POST /priority/replay – batch replay a list of snapshot_ids against a
  # specific strategy. Returns one frozen PriorityScore per input.
  def replay
    strategy = ScoringStrategy.find(params.require(:strategy_id))
    snapshot_ids = Array(params[:snapshot_ids]).map(&:to_i)

    scores = ApplicationRecord.transaction do
      snapshot_ids.map do |sid|
        snapshot = EvidenceSnapshot.find(sid)
        Scoring::PriorityComputer.call(
          snapshot, strategy: strategy, now: Time.current
        )
      end
    end

    render json: { items: scores.map { |s| serialize_score(s) } }
  end

  # POST /priority/compute_latest – compute scores for the latest snapshot
  # of every hazard point using the current published strategy. Bounded to
  # make 10k+ point batches feasible.
  def compute_latest
    now = Time.current
    point_ids = params[:hazard_point_ids]

    snapshots = EvidenceSnapshot
                .where("id IN (#{Scoring::QueueService.latest_snapshot_sql})")
    snapshots = snapshots.where(hazard_point_id: point_ids) if point_ids.present?

    scores = ApplicationRecord.transaction do
      snapshots.map do |snap|
        Scoring::PriorityComputer.call(snap, now: now)
      end
    end

    render json: { computed: scores.size }
  end

  private

  def find_strategy
    return nil unless params[:strategy_id].present?

    ScoringStrategy.find(params[:strategy_id])
  end

  def serialize_score(score)
    {
      id: score.id,
      hazard_point_id: score.hazard_point_id,
      evidence_snapshot_id: score.evidence_snapshot_id,
      scoring_strategy_id: score.scoring_strategy_id,
      version_code: score.explanation&.dig("version_code"),
      snapshot_time: score.snapshot_time.iso8601,
      total_score: score.total_score,
      risk_level: score.risk_level,
      dispatch_status: score.dispatch_status,
      road_accessible: score.road_accessible,
      components: score.components,
      hazard_point: score.hazard_point && {
        id: score.hazard_point.id,
        name: score.hazard_point.name,
        kind: score.hazard_point.kind
      }
    }
  end
end
