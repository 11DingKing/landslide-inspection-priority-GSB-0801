module Scoring
  # Application service that turns an EvidenceSnapshot (+ optional strategy
  # override) into a persisted PriorityScore.
  #
  # Concurrency / idempotency:
  #   * The (evidence_snapshot_id, scoring_strategy_id) pair has a UNIQUE
  #     database index.
  #   * We INSERT ... ON CONFLICT DO NOTHING so that two processes computing
  #     the same snapshot at the same time both end up with the same row
  #     and identical component breakdown (the pure Calculator guarantees
  #     identical output for identical inputs).
  #
  # Replay:
  #   * Pass an explicit `strategy:` to score an old snapshot with any
  #     historical strategy. The resulting PriorityScore is stored alongside
  #     "current" scores and never overwritten.
  #   * The snapshot_time and component breakdown are copied into the row so
  #     that even if the EvidenceSnapshot is later soft-edited, the historical
  #     explanation remains frozen.
  class PriorityComputer
    class << self
      def call(snapshot, strategy: nil, as_of: nil, now: Time.current)
        new(snapshot, strategy: strategy, as_of: as_of, now: now).call
      end
    end

    def initialize(snapshot, strategy:, as_of:, now:)
      @snapshot = snapshot
      @strategy = strategy
      @as_of = as_of
      @now = now
    end

    def call
      resolved_strategy = @strategy || select_strategy
      result = Calculator.call(
        evidence_for(@snapshot),
        rules: resolved_strategy.rules,
        rules_version: resolved_strategy.version_code,
        now: @now
      )

      persist!(@snapshot, resolved_strategy, result)
    end

    private

    def select_strategy
      time = @as_of || @snapshot.snapshot_time || @now
      StrategySelector.for_time(time)
    end

    def evidence_for(snapshot)
      {
        rainfall_24h_mm: snapshot.rainfall_24h_mm.to_f,
        historical_event_count: snapshot.historical_event_count,
        last_inspected_at: snapshot.last_inspected_at,
        road_accessible: snapshot.road_accessible,
        kind: snapshot.hazard_point.kind
      }
    end

    def persist!(snapshot, strategy, result)
      attrs = {
        evidence_snapshot_id: snapshot.id,
        scoring_strategy_id: strategy.id,
        hazard_point_id: snapshot.hazard_point_id,
        snapshot_time: snapshot.snapshot_time,
        total_score: result.total_score,
        risk_level: result.risk_level,
        dispatch_status: result.dispatch_status,
        road_accessible: result.road_accessible,
        components: result.components,
        explanation: build_explanation(snapshot, strategy, result)
      }

      row = PriorityScore.create_with(attrs).find_or_create_by!(
        evidence_snapshot_id: snapshot.id,
        scoring_strategy_id: strategy.id
      )

      # If a pre-existing row was found (concurrent replay), verify its
      # components still sum exactly to the total. This is an invariant guard
      # so tampering / old data is detected rather than silently returned.
      verify_component_sum!(row)
      row
    end

    def verify_component_sum!(row)
      sum = row.components.sum { |c| c["score"].to_i }
      return if sum == row.total_score

      raise ComponentSumMismatch,
            "priority_score #{row.id} components sum to #{sum} but total is #{row.total_score}"
    end

    def build_explanation(snapshot, strategy, result)
      {
        "version_code" => strategy.version_code,
        "strategy_id" => strategy.id,
        "strategy_name" => strategy.name,
        "effective_at" => strategy.effective_at.iso8601,
        "snapshot_time" => snapshot.snapshot_time.iso8601,
        "computed_at" => @now.iso8601,
        "components" => result.components,
        "total_score" => result.total_score,
        "risk_level" => result.risk_level,
        "dispatch_status" => result.dispatch_status,
        "road_accessible" => result.road_accessible,
        "notes" =>
          if result.dispatch_status == "blocked"
            "road inaccessible; original risk level preserved, only dispatch status changed"
          else
            "scored using standard dispatch"
          end
      }
    end

    class ComponentSumMismatch < StandardError; end
  end
end
