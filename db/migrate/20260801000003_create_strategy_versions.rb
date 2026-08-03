# frozen_string_literal: true

# Strategy versions are published for a half-open effective range
# [effective_from, effective_to). A PostgreSQL exclusion constraint guarantees
# that no two *published* versions can overlap: publishing two candidates at
# the same effective moment fails atomically for one of them (409 Conflict),
# so the strategy that applies to any snapshot time is always unique.
class CreateStrategyVersions < ActiveRecord::Migration[8.1]
  def up
    enable_extension :btree_gist

    create_table :strategy_versions do |t|
      t.integer :version, null: false
      t.string :status, null: false, default: "draft"
      t.column :effective_range, :tstzrange, null: false
      t.jsonb :rules, null: false
      t.datetime :published_at, precision: 6
      t.timestamps
    end
    add_index :strategy_versions, :version, unique: true
    add_check_constraint :strategy_versions,
                         "status IN ('draft', 'published', 'retired')",
                         name: "strategy_versions_status_check"

    execute <<~SQL
      ALTER TABLE strategy_versions
        ADD CONSTRAINT strategy_versions_no_published_overlap
        EXCLUDE USING gist (effective_range WITH &&)
        WHERE (status = 'published');
    SQL
  end

  def down
    drop_table :strategy_versions
  end
end
