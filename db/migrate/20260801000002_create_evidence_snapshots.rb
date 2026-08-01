class CreateEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :evidence_snapshots do |t|
      t.references :hazard_point, null: false, foreign_key: true

      # captured_at is the LOCKED evidence instant. Policy selection and every
      # replay resolve against this timestamp, so it must never change after
      # creation (enforced by the model immutability guard).
      t.datetime :captured_at, null: false

      # Raw evidence facts. Kept as immutable primitives so a snapshot can be
      # rescored by any policy version without re-reading mutable state.
      t.decimal :rainfall_mm_24h, precision: 8, scale: 2, null: false, default: 0
      t.integer :historical_event_count, null: false, default: 0
      t.boolean :road_accessible, null: false, default: true
      t.datetime :point_last_inspected_at

      # Deterministic digest of the frozen facts. Used to detect any attempt to
      # mutate an immutable snapshot and to key idempotent operations.
      t.string :content_digest, null: false

      t.timestamps
    end

    add_index :evidence_snapshots, %i[hazard_point_id captured_at]
    add_index :evidence_snapshots, :content_digest
  end
end
