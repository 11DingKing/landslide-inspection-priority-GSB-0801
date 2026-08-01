# frozen_string_literal: true

# A caller-supplied stable business identifier for each evidence snapshot.
# Resubmitting the same identifier with the same content is idempotent;
# the same identifier with different content is a conflict.
class AddClientReferenceToEvidenceSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :evidence_snapshots, :client_reference, :string
    add_index :evidence_snapshots, :client_reference, unique: true
  end
end
