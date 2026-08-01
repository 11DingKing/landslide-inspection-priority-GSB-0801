class CreatePriorityScores < ActiveRecord::Migration[8.1]
  def change
    create_table :priority_scores do |t|
      t.references :evidence_snapshot, null: false, foreign_key: true
      t.references :scoring_policy, null: false, foreign_key: true
      # Denormalised for queue ordering / keyset pagination without a join.
      t.references :hazard_point, null: false, foreign_key: true

      # LOCKED component vocabulary and ranges. Integer points only, so the
      # explanation can assert an exact (not floating) sum invariant.
      #   rainfall_score  0..40
      #   history_score   0..25
      #   recency_score   0..20
      #   exposure_score  0..15
      t.integer :rainfall_score, null: false
      t.integer :history_score, null: false
      t.integer :recency_score, null: false
      t.integer :exposure_score, null: false
      # total_score 0..100, always == sum of the four components (DB-enforced).
      t.integer :total_score, null: false

      # Intrinsic hazard severity. NEVER lowered by road inaccessibility.
      t.string :risk_level, null: false
      # Scheduling channel only. "blocked" when the road is closed; the risk
      # level and scores above remain untouched.
      t.string :scheduling_status, null: false, default: "schedulable"

      # Provenance for explainability: which policy version produced this and
      # against which frozen evidence instant.
      t.string :policy_version, null: false
      t.datetime :evidence_captured_at, null: false

      t.timestamps
    end

    # One score per (snapshot, policy). Concurrent recomputation upserts onto
    # this key, so racing workers converge to a single row instead of dupes.
    add_index :priority_scores, %i[evidence_snapshot_id scoring_policy_id],
              unique: true, name: "index_priority_scores_on_snapshot_and_policy"

    # Keyset pagination index: stable total DESC, tie-broken by immutable id ASC.
    add_index :priority_scores, %i[total_score id],
              order: { total_score: :desc, id: :asc },
              name: "index_priority_scores_on_total_and_id"

    add_check_constraint :priority_scores,
                         "rainfall_score BETWEEN 0 AND 40",
                         name: "priority_scores_rainfall_range"
    add_check_constraint :priority_scores,
                         "history_score BETWEEN 0 AND 25",
                         name: "priority_scores_history_range"
    add_check_constraint :priority_scores,
                         "recency_score BETWEEN 0 AND 20",
                         name: "priority_scores_recency_range"
    add_check_constraint :priority_scores,
                         "exposure_score BETWEEN 0 AND 15",
                         name: "priority_scores_exposure_range"
    add_check_constraint :priority_scores,
                         "total_score BETWEEN 0 AND 100",
                         name: "priority_scores_total_range"
    # The sum invariant, guaranteed even against direct SQL writes.
    add_check_constraint :priority_scores,
                         "total_score = rainfall_score + history_score + recency_score + exposure_score",
                         name: "priority_scores_components_sum_to_total"
    add_check_constraint :priority_scores,
                         "scheduling_status IN ('schedulable', 'blocked')",
                         name: "priority_scores_scheduling_status_check"
  end
end
