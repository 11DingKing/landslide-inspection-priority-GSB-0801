class CreateQueueSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :queue_snapshots do |t|
      t.string :name, null: false
      t.references :scoring_strategy, null: false, foreign_key: { on_delete: :restrict }
      t.timestamp :snapshot_at, null: false
      t.integer :total_count, null: false, default: 0
      t.boolean :include_blocked, null: false, default: true
      t.string :risk_level_filter
      t.string :dispatch_status_filter
      t.jsonb :filters_json, null: false, default: {}
      t.timestamps
    end

    add_index :queue_snapshots, :name, unique: true
    add_index :queue_snapshots, :snapshot_at

    create_table :queue_snapshot_items do |t|
      t.references :queue_snapshot, null: false, foreign_key: { on_delete: :cascade }
      t.references :priority_score, null: false, foreign_key: { on_delete: :restrict }
      t.references :hazard_point, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.integer :total_score, null: false
      t.string :risk_level, null: false
      t.string :dispatch_status, null: false
      t.timestamps
    end

    add_index :queue_snapshot_items,
              %i[queue_snapshot_id position],
              unique: true,
              name: "idx_queue_items_snapshot_position"
    add_index :queue_snapshot_items,
              %i[queue_snapshot_id priority_score_id],
              unique: true,
              name: "idx_queue_items_snapshot_score"
  end
end
