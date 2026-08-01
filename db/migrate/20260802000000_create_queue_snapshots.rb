# frozen_string_literal: true

# Named, immutable read snapshots of the inspection queue. A snapshot pins
# the strategy round applicable at capture time and materializes exactly the
# score records that were current, so a cursor traversal over the snapshot
# can never skip or duplicate entries when the live "current" pointer moves.
class CreateQueueSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :queue_snapshots do |t|
      t.string :name, null: false
      t.references :strategy_version, null: false, foreign_key: true
      t.timestamps
    end
    add_index :queue_snapshots, :name, unique: true

    create_table :queue_snapshot_entries do |t|
      t.references :queue_snapshot, null: false, foreign_key: true
      t.references :score_record, null: false, foreign_key: true
    end
    add_index :queue_snapshot_entries, %i[queue_snapshot_id score_record_id],
              unique: true, name: "idx_queue_snapshot_entries_unique"
  end
end
