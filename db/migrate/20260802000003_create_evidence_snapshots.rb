class CreateEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def up
    create_table :evidence_snapshots do |t|
      t.references :hazard_point, null: false, foreign_key: true
      t.references :scoring_strategy, null: false, foreign_key: true

      t.datetime :snapshot_at, null: false

      t.decimal :rainfall_24h_mm, precision: 8, scale: 1, null: false, default: 0
      t.integer :historical_event_count, null: false, default: 0
      t.string :point_type, null: false
      t.string :road_status, null: false
      t.datetime :last_inspected_at

      t.integer :total_score, null: false
      t.string :risk_level, null: false
      t.string :dispatch_status, null: false
      t.jsonb :score_breakdown, null: false
      t.jsonb :explanation, null: false, default: {}

      t.timestamps
    end

    add_index :evidence_snapshots, [:hazard_point_id, :snapshot_at]
    add_index :evidence_snapshots, [:total_score, :id]
    add_index :evidence_snapshots, [:dispatch_status, :total_score, :id],
              name: "index_evidence_snapshots_for_queue"
    add_index :evidence_snapshots, :snapshot_at

    execute <<~SQL
      CREATE OR REPLACE FUNCTION evidence_snapshots_immutable() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'evidence_snapshots are immutable and cannot be updated or deleted';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER evidence_snapshots_no_update
        BEFORE UPDATE ON evidence_snapshots
        FOR EACH ROW EXECUTE FUNCTION evidence_snapshots_immutable();

      CREATE TRIGGER evidence_snapshots_no_delete
        BEFORE DELETE ON evidence_snapshots
        FOR EACH ROW EXECUTE FUNCTION evidence_snapshots_immutable();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS evidence_snapshots_no_delete ON evidence_snapshots;
      DROP TRIGGER IF EXISTS evidence_snapshots_no_update ON evidence_snapshots;
      DROP FUNCTION IF EXISTS evidence_snapshots_immutable();
    SQL

    drop_table :evidence_snapshots
  end
end
