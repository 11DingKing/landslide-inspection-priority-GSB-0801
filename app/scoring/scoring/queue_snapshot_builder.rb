module Scoring
  # Builds a named queue-read snapshot by freezing the `current` priority scores
  # of a pinned policy ("round") into immutable items. The freeze happens in one
  # transaction so the captured membership is internally consistent; afterwards
  # the snapshot is stable no matter how the live `current` scores move.
  class QueueSnapshotBuilder
    def initialize(policy:, name:, built_at: Time.current)
      @policy = policy
      @name = name
      @built_at = built_at
    end

    def call
      ActiveRecord::Base.transaction do
        snapshot = QueueSnapshot.create!(
          name: @name, scoring_policy: @policy, built_at: @built_at
        )

        # Membership: the current scores produced by the pinned policy. Ordered
        # deterministically so the frozen rows are laid down consistently.
        scores = PriorityScore
          .where(scoring_policy_id: @policy.id, current: true)
          .order(total_score: :desc, hazard_point_id: :asc)

        rows = scores.map do |ps|
          {
            queue_snapshot_id: snapshot.id,
            priority_score_id: ps.id,
            hazard_point_id: ps.hazard_point_id,
            total_score: ps.total_score,
            risk_level: ps.risk_level,
            scheduling_status: ps.scheduling_status,
            policy_version: ps.policy_version,
            evidence_snapshot_id: ps.evidence_snapshot_id,
            created_at: @built_at,
            updated_at: @built_at
          }
        end
        QueueSnapshotItem.insert_all!(rows) if rows.any?

        snapshot
      end
    end
  end
end
