module Scoring
  # Application service that turns an EvidenceSnapshot (+ optional strategy
  # override) into a persisted PriorityScore.
  #
  # Two kinds of scores are supported:
  #
  #   * kind = "current" (default when no explicit strategy is given)
  #       The score produced by the strategy effective at the snapshot's time.
  #       The partial unique index idx_priority_scores_one_current_per_snapshot
  #       guarantees at most one current row per evidence_snapshot_id. This is
  #       what makes "concurrent computation leaves one current score" work.
  #
  #   * kind = "replay" (when an explicit strategy: is passed)
  #       The score produced by an arbitrary historical / future strategy.
  #       Replay rows never collide with current rows, and each (snapshot,
  #       strategy) pair is unique via idx_priority_scores_snapshot_strategy.
  #
  # Replay design:
  #   * The snapshot_time and component breakdown are copied into the row so
  #     that even if the EvidenceSnapshot is later edited, the historical
  #     explanation remains frozen.
  #   * v1 is never retired; old snapshots keep their current row bound to v1
  #     even after v2 is published, because the strategy selector picks
  #     effective_at <= snapshot_time.
  class PriorityComputer
    CURRENT_KIND = "current"
    REPLAY_KIND  = "replay"

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
      kind = @strategy ? REPLAY_KIND : CURRENT_KIND
      result = Calculator.call(
        evidence_for(@snapshot),
        rules: resolved_strategy.rules,
        rules_version: resolved_strategy.version_code,
        now: @now
      )

      persist!(@snapshot, resolved_strategy, result, kind)
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

    def persist!(snapshot, strategy, result, kind)
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
        explanation: build_explanation(snapshot, strategy, result, kind),
        kind: kind
      }

      row = existing_row(snapshot, strategy)
      return verify_and_return(row) if row

      create_or_find_existing(attrs)
    end

    def existing_row(snapshot, strategy)
      PriorityScore.find_by(
        evidence_snapshot_id: snapshot.id,
        scoring_strategy_id: strategy.id
      )
    end

    def verify_and_return(row)
      verify_component_sum!(row)
      row
    end

    def create_or_find_existing(attrs)
      # Wrap the INSERT in a savepoint so that a unique-constraint failure
      # from a concurrent caller does not abort the outer transaction. This
      # is what makes the operation safe under rspec transactional fixtures
      # as well as production transactions.
      PriorityScore.transaction(requires_new: true) do
        PriorityScore.create!(attrs).tap { |row| verify_component_sum!(row) }
      end
    rescue ActiveRecord::RecordNotUnique
      PriorityScore.find_by!(
        evidence_snapshot_id: attrs[:evidence_snapshot_id],
        scoring_strategy_id: attrs[:scoring_strategy_id]
      ).tap { |row| verify_component_sum!(row) }
    end

    def verify_component_sum!(row)
      sum = row.components.sum { |c| c["score"].to_i }
      return if sum == row.total_score

      raise ComponentSumMismatch,
            "priority_score #{row.id} components sum to #{sum} but total is #{row.total_score}"
    end

    def build_explanation(snapshot, strategy, result, kind)
      {
        "version_code" => strategy.version_code,
        "strategy_id" => strategy.id,
        "strategy_name" => strategy.name,
        "effective_at" => strategy.effective_at.iso8601,
        "snapshot_time" => snapshot.snapshot_time.iso8601,
        "computed_at" => @now.iso8601,
        "score_kind" => kind,
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
