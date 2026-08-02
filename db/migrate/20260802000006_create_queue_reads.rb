class CreateQueueReads < ActiveRecord::Migration[8.1]
  def change
    create_table :queue_reads do |t|
      t.string :business_id, null: false
      t.integer :strategy_version, null: false
      t.datetime :cutoff_at, null: false
      t.string :dispatch_status

      t.timestamps
    end

    add_index :queue_reads, :business_id, unique: true
    add_index :queue_reads, :cutoff_at
    add_index :evidence_snapshots, [:scoring_strategy_id, :snapshot_at],
              name: "index_evidence_snapshots_on_strategy_and_snapshot_at"
  end
end
