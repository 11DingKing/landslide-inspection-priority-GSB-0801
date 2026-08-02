class AddBusinessKeyToEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :evidence_snapshots, :business_key, :string

    # The same business_key must not appear twice, regardless of whether two
    # callers race to create it. The partial index keeps legacy rows (with
    # NULL business_key) untouched.
    add_index :evidence_snapshots, :business_key,
              unique: true,
              where: "business_key IS NOT NULL",
              name: "idx_evidence_snapshots_business_key_unique"
  end
end
