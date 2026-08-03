module Scoring
  # Computes a priority score for a snapshot and persists it idempotently.
  #
  # Concurrency contract (two levels):
  #   * (snapshot, policy) idempotency: workers scoring the same pair race onto
  #     index_priority_scores_on_snapshot_and_policy; an upsert makes the loser
  #     update the same row, so both observers see one converged record.
  #   * one "current" score per hazard point: we take a row lock on the hazard
  #     point before transitioning the current flag, so concurrent computes are
  #     serialised and exactly one row ends up current (backed by the partial
  #     unique index index_priority_scores_one_current_per_point).
  #
  # This service orchestrates persistence only. Every number it stores comes
  # from Scoring::Engine; it applies no scoring rules of its own.
  class Materializer
    Outcome = Data.define(:priority_score, :result, :policy)

    def initialize(snapshot)
      @snapshot = snapshot
    end

    # policy:       resolve the authoritative policy for the snapshot's frozen
    #               instant unless one is supplied (replay of a specific version).
    # make_current: :auto (default) marks this score current only when its
    #               snapshot is the latest evidence for the hazard point, so an
    #               audit replay of an older snapshot never steals current.
    #               true forces current; false never sets current.
    def call(policy: nil, make_current: :auto)
      policy ||= ScoringPolicy.authoritative_for(@snapshot.captured_at)
      raise NoAuthoritativePolicyError.new(@snapshot.captured_at) if policy.nil?

      result = Engine.new(policy.definition).score(
        facts: @snapshot,
        category: @snapshot.hazard_point.category,
        policy_version: policy.version
      )

      record = nil
      ActiveRecord::Base.transaction do
        # Serialise current-flag transitions per hazard point.
        HazardPoint.lock.find(@snapshot.hazard_point_id)
        record = upsert(policy, result)
        apply_current_flag(record, make_current)
        record.reload
      end
      Outcome.new(priority_score: record, result: result, policy: policy)
    end

    private

    def apply_current_flag(record, make_current)
      should = case make_current
               when true then true
               when false then false
               else latest_snapshot_for_point?
               end
      return unless should

      # Demote any existing current row for this point, then promote this one.
      # Both run inside the per-point row lock, so the partial unique index is
      # never violated and exactly one row remains current.
      PriorityScore.where(hazard_point_id: record.hazard_point_id, current: true)
                   .where.not(id: record.id)
                   .update_all(current: false)
      record.update_columns(current: true) unless record.current
    end

    def latest_snapshot_for_point?
      latest_id = EvidenceSnapshot
        .where(hazard_point_id: @snapshot.hazard_point_id)
        .order(captured_at: :desc, id: :desc)
        .limit(1)
        .pick(:id)
      latest_id == @snapshot.id
    end

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
      # current is intentionally left out of update_only so a re-score never
      # clobbers the flag; apply_current_flag owns that transition.
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
