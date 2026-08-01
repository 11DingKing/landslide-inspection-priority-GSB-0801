# frozen_string_literal: true

# Evidence snapshots are immutable: once inserted they can never be updated
# or deleted. Immutability is enforced at the database level (trigger) so no
# application path can silently rewrite yesterday's evidence.
class CreateEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def up
    create_table :evidence_snapshots do |t|
      t.references :hazard_point, null: false, foreign_key: true
      t.numeric :rainfall_24h_mm, precision: 7, scale: 1, null: false
      t.integer :historical_event_count, null: false, default: 0
      t.datetime :last_inspected_at, precision: 6, null: true
      t.boolean :road_accessible, null: false, default: true
      t.datetime :captured_at, precision: 6, null: false
      t.text :note
      t.timestamps
    end
    add_index :evidence_snapshots, %i[hazard_point_id captured_at]

    execute <<~SQL
      CREATE OR REPLACE FUNCTION evidence_snapshots_immutable() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'evidence_snapshots are immutable: % is not allowed', TG_OP
          USING ERRCODE = 'raise_exception';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER evidence_snapshots_no_update
        BEFORE UPDATE OR DELETE ON evidence_snapshots
        FOR EACH ROW EXECUTE FUNCTION evidence_snapshots_immutable();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS evidence_snapshots_no_update ON evidence_snapshots;
      DROP FUNCTION IF EXISTS evidence_snapshots_immutable();
    SQL
    drop_table :evidence_snapshots
  end
end
