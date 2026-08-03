class CreateEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :evidence_snapshots do |t|
      t.references :hazard_point, null: false, foreign_key: { on_delete: :restrict }
      t.timestamp :snapshot_time, null: false
      t.decimal :rainfall_24h_mm, precision: 7, scale: 2, null: false
      t.integer :historical_event_count, null: false, default: 0
      t.timestamp :last_inspected_at
      t.boolean :road_accessible, null: false, default: true
      t.boolean :immutable, null: false, default: false
      t.jsonb :raw_payload, null: false, default: {}
      t.text :source_note
      t.timestamps
    end

    add_index :evidence_snapshots, %i[hazard_point_id snapshot_time],
              name: "idx_evidence_snapshots_point_time"
    add_index :evidence_snapshots, :snapshot_time
  end
end
