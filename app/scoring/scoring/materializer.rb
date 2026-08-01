module Scoring
  # Computes a priority score for a snapshot and persists it idempotently.
  #
  # Concurrency contract: two workers scoring the same (snapshot, policy) race
  # onto the unique index index_priority_scores_on_snapshot_and_policy. We use
  # an upsert so the loser of the race updates the same row instead of raising —
  # both observers end up seeing one identical, converged record.
  #
  # This service orchestrates persistence only. Every number it stores comes
  # from Scoring::Engine; it applies no scoring rules of its own.
  class Materializer
    Outcome = Data.define(:priority_score, :result, :policy)

    def initialize(snapshot)
      @snapshot = snapshot
    end

    # Resolve the authoritative policy for the snapshot's frozen instant unless
    # one is supplied (replay of a specific version).
    def call(policy: nil)
      policy ||= ScoringPolicy.authoritative_for(@snapshot.captured_at)
      raise NoAuthoritativePolicyError.new(@snapshot.captured_at) if policy.nil?

      result = Engine.new(policy.definition).score(
        facts: @snapshot,
        category: @snapshot.hazard_point.category,
        policy_version: policy.version
      )

      record = upsert(policy, result)
      Outcome.new(priority_score: record, result: result, policy: policy)
    end

    private

    def upsert(policy, result)
      attrs = {
        evidence_snapshot_id: @snapshot.id,
        scoring_policy_id: policy.id,
        hazard_point_id: @snapshot.hazard_point_id,
        rainfall_score: result.rainfall_score,
        history_score: result.history_score,
        recency_score: result.recency_score,
        exposure_score: result.exposure_score,
        total_score: result.total_score,
        risk_level: result.risk_level,
        scheduling_status: result.scheduling_status,
        policy_version: policy.version,
        evidence_captured_at: @snapshot.captured_at
      }

      # Rails manages created_at/updated_at for the upsert (record_timestamps).
      PriorityScore.upsert(
        attrs,
        unique_by: :index_priority_scores_on_snapshot_and_policy,
        update_only: %i[
          rainfall_score history_score recency_score exposure_score
          total_score risk_level scheduling_status policy_version
          evidence_captured_at
        ]
      )

      PriorityScore.find_by!(
        evidence_snapshot_id: @snapshot.id,
        scoring_policy_id: policy.id
      )
    end
  end
end
