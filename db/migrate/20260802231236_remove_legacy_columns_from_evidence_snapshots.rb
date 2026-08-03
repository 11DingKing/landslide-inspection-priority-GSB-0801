class RemoveLegacyColumnsFromEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def change
    remove_column :evidence_snapshots, :business_identifier, :string
    remove_column :evidence_snapshots, :payload_hash, :string
  end
end
