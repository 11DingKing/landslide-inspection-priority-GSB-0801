# frozen_string_literal: true

class CreateScoreRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :score_records do |t|
      t.references :hazard_point, null: false, foreign_key: true
      t.references :evidence_snapshot, null: false, foreign_key: true
      t.references :strategy_version, null: false, foreign_key: true
      t.jsonb :components, null: false
      t.integer :total_score, null: false
      t.string :risk_level, null: false
      t.string :scheduling_status, null: false
      t.boolean :is_current, null: false, default: true
      t.datetime :computed_at, precision: 6, null: false
      t.timestamps
    end

    # Idempotent computation: the same snapshot scored under the same strategy
    # version can only ever produce one record, no matter how many concurrent
    # workers compute it.
    add_index :score_records, %i[evidence_snapshot_id strategy_version_id],
              unique: true, name: "idx_score_records_snapshot_strategy"

    # Exactly one current score per hazard point.
    add_index :score_records, :hazard_point_id, unique: true,
              where: "is_current", name: "idx_score_records_current_per_point"

    # Keyset-paginated queue ordering: (total_score DESC, id ASC).
    add_index :score_records, %i[total_score id],
              order: { total_score: :desc, id: :asc },
              where: "is_current", name: "idx_score_records_queue"

    add_check_constraint :score_records,
                         "risk_level IN ('high', 'medium', 'low')",
                         name: "score_records_risk_level_check"
    add_check_constraint :score_records,
                         "scheduling_status IN ('schedulable', 'blocked')",
                         name: "score_records_scheduling_status_check"
  end
end
