class AddBusinessIdToEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :evidence_snapshots, :business_id, :string

    add_index :evidence_snapshots, :business_id,
              unique: true,
              where: "business_id IS NOT NULL",
              name: "index_evidence_snapshots_on_business_id_unique"
  end
end
