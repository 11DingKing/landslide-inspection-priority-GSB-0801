class CreateQueueSnapshots < ActiveRecord::Migration[8.1]
  # A queue-read snapshot is a named, immutable, frozen copy of one policy's
  # `current` ranking at build time. A traversal pinned to a snapshot walks its
  # frozen items only, so recomputes that move `current` scores underneath it
  # can neither add, drop, nor reorder items — no misses, no duplicates. A new
  # snapshot re-reads live state and therefore sees the updates.
  def change
    create_table :queue_snapshots do |t|
      t.string :name, null: false
      # Pins the traversal to a policy version ("round"), e.g. v2. Membership is
      # frozen from this policy's current scores.
      t.references :scoring_policy, null: false, foreign_key: true
      t.datetime :built_at, null: false

      t.timestamps
    end
    add_index :queue_snapshots, :name, unique: true

    create_table :queue_snapshot_items do |t|
      t.references :queue_snapshot, null: false, foreign_key: true
      # The exact priority score row this frozen item points at, so explanations
      # still replay by the original v1/v2 boundary regardless of later current
      # movement.
      t.references :priority_score, null: false, foreign_key: true
      t.references :hazard_point, null: false, foreign_key: true

      # Frozen ordering keys + display fields, copied at build time so the read
      # never depends on the (mutable) live priority_scores.
      t.integer :total_score, null: false
      t.string :risk_level, null: false
      t.string :scheduling_status, null: false
      t.string :policy_version, null: false
      t.bigint :evidence_snapshot_id, null: false

      t.timestamps
    end

    # One frozen entry per hazard point per snapshot.
    add_index :queue_snapshot_items, %i[queue_snapshot_id hazard_point_id],
              unique: true, name: "index_queue_items_on_snapshot_and_point"
    # Keyset pagination index: total DESC, tie-broken by immutable hazard_point_id.
    add_index :queue_snapshot_items, %i[queue_snapshot_id total_score hazard_point_id],
              order: { total_score: :desc, hazard_point_id: :asc },
              name: "index_queue_items_keyset"
  end
end
