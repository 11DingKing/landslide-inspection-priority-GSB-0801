module Scoring
  # Builds the explainable API payloads. Centralises the response shape so both
  # the compute and explain endpoints emit identical, self-describing output.
  #
  # The explanation asserts the sum invariant at serialization time as a final
  # guard: components must add up to exactly the total, or we refuse to present
  # a misleading explanation.
  module Presenter
    module_function

    def explanation(priority_score)
      components = component_rows(priority_score)
      component_total = components.sum { |c| c[:score] }

      unless component_total == priority_score.total_score
        raise "explanation invariant violated: components sum to #{component_total} " \
              "but total_score is #{priority_score.total_score}"
      end

      {
        hazard_point: {
          id: priority_score.hazard_point_id,
          code: priority_score.hazard_point.code,
          name: priority_score.hazard_point.name,
          category: priority_score.hazard_point.category
        },
        evidence_snapshot: {
          id: priority_score.evidence_snapshot_id,
          business_key: priority_score.evidence_snapshot.business_key,
          captured_at: priority_score.evidence_captured_at.utc.iso8601,
          rainfall_mm_24h: priority_score.evidence_snapshot.rainfall_mm_24h.to_s("F"),
          historical_event_count: priority_score.evidence_snapshot.historical_event_count,
          road_accessible: priority_score.evidence_snapshot.road_accessible,
          content_digest: priority_score.evidence_snapshot.content_digest
        },
        scoring_policy: {
          id: priority_score.scoring_policy_id,
          version: priority_score.policy_version,
          effective_from: priority_score.scoring_policy.effective_from.utc.iso8601,
          effective_until: priority_score.scoring_policy.effective_until&.utc&.iso8601
        },
        components: components,
        total_score: priority_score.total_score,
        components_sum: component_total,
        risk_level: priority_score.risk_level,
        scheduling_status: priority_score.scheduling_status,
        road_blocked: priority_score.blocked?,
        current: priority_score.current
      }
    end

    def queue_item(priority_score)
      {
        hazard_point_id: priority_score.hazard_point_id,
        hazard_point_code: priority_score.hazard_point.code,
        total_score: priority_score.total_score,
        risk_level: priority_score.risk_level,
        scheduling_status: priority_score.scheduling_status,
        policy_version: priority_score.policy_version,
        evidence_snapshot_id: priority_score.evidence_snapshot_id,
        current: priority_score.current
      }
    end

    def component_rows(priority_score)
      [
        { name: "rainfall", score: priority_score.rainfall_score, max: 40 },
        { name: "history",  score: priority_score.history_score,  max: 25 },
        { name: "recency",  score: priority_score.recency_score,  max: 20 },
        { name: "exposure", score: priority_score.exposure_score, max: 15 }
      ]
    end
  end
end
