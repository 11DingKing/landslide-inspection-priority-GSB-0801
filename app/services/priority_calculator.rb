class PriorityCalculator
  class Error < StandardError; end
  class MissingStrategy < Error; end

  def self.call(hazard_point, at: Time.current, strategy: nil,
                strategy_version: nil, rainfall_24h_mm: nil)
    new(hazard_point).calculate(at: at, strategy: strategy,
                                strategy_version: strategy_version,
                                rainfall_24h_mm: rainfall_24h_mm)
  end

  def initialize(hazard_point)
    @hazard_point = hazard_point
  end

  def calculate(at: Time.current, strategy: nil, strategy_version: nil,
                rainfall_24h_mm: nil)
    time = at.respond_to?(:to_time) ? at.to_time.utc : Time.current.utc
    resolved = resolve_strategy(strategy, strategy_version, time)
    engine = ScoringEngine.new(resolved)

    evidence = build_evidence(time, rainfall_24h_mm)
    result = engine.score(evidence)

    create_snapshot!(time, resolved, evidence, result)
  end

  def self.replay(snapshot, strategy_version:)
    strategy = StrategyResolver.find_version(strategy_version)
    new(snapshot.hazard_point).replay_snapshot(snapshot, strategy)
  end

  def replay_snapshot(snapshot, strategy)
    engine = ScoringEngine.new(strategy)
    evidence = {
      rainfall_24h_mm: snapshot.rainfall_24h_mm.to_f,
      historical_event_count: snapshot.historical_event_count,
      point_type: snapshot.point_type,
      road_status: snapshot.road_status,
      last_inspected_at: snapshot.last_inspected_at,
      snapshot_at: snapshot.snapshot_at
    }
    result = engine.score(evidence)
    create_snapshot!(snapshot.snapshot_at, strategy, evidence, result)
  end

  private

  def resolve_strategy(strategy, strategy_version, time)
    return strategy if strategy
    return StrategyResolver.find_version(strategy_version) if strategy_version

    StrategyResolver.resolve!(time)
  rescue StrategyResolver::NoActiveStrategy => e
    raise MissingStrategy, e.message
  end

  def build_evidence(time, rainfall_override)
    rainfall = rainfall_override || @hazard_point.latest_rainfall_24h_mm
    {
      rainfall_24h_mm: rainfall.to_f,
      historical_event_count: @hazard_point.historical_event_count,
      point_type: @hazard_point.point_type,
      road_status: @hazard_point.road_status,
      last_inspected_at: @hazard_point.last_inspected_at,
      snapshot_at: time
    }
  end

  def create_snapshot!(time, strategy, evidence, result)
    # Use insert! to bypass the after_initialize readonly guard on new records,
    # while still relying on DB constraints and the immutable trigger.
    EvidenceSnapshot.create!(
      hazard_point_id: @hazard_point.id,
      scoring_strategy_id: strategy.id,
      snapshot_at: time,
      rainfall_24h_mm: evidence[:rainfall_24h_mm],
      historical_event_count: evidence[:historical_event_count],
      point_type: evidence[:point_type],
      road_status: evidence[:road_status],
      last_inspected_at: evidence[:last_inspected_at],
      total_score: result.total_score,
      risk_level: result.risk_level,
      dispatch_status: result.dispatch_status,
      score_breakdown: result.score_breakdown.map(&:stringify_keys),
      explanation: result.explanation
    )
  end
end
