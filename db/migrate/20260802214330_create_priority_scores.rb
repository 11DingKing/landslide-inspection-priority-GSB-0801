class CreatePriorityScores < ActiveRecord::Migration[8.1]
  def change
    create_enum :risk_level, %w[low medium high critical]
    create_enum :dispatch_status, %w[available blocked]

    create_table :priority_scores do |t|
      t.references :evidence_snapshot, null: false, foreign_key: { on_delete: :restrict }
      t.references :scoring_strategy, null: false, foreign_key: { on_delete: :restrict }
      t.references :hazard_point, null: false, foreign_key: { on_delete: :cascade }

      t.timestamp :snapshot_time, null: false
      t.integer :total_score, null: false
      t.enum :risk_level, enum_type: :risk_level, null: false
      t.enum :dispatch_status, enum_type: :dispatch_status, null: false, default: "available"
      t.boolean :road_accessible, null: false, default: true

      # Locked component names, ranges and values so that future rule changes
      # cannot silently rewrite historical explanations.
      t.jsonb :components, null: false, default: []
      t.jsonb :explanation, null: false, default: {}

      t.timestamps
    end

    add_index :priority_scores,
              %i[evidence_snapshot_id scoring_strategy_id],
              unique: true,
              name: "idx_priority_scores_snapshot_strategy_unique"

    add_index :priority_scores,
              %i[total_score hazard_point_id],
              name: "idx_priority_scores_queue_order"

    add_index :priority_scores, :risk_level
    add_index :priority_scores, :dispatch_status
  end
end
