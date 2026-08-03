class CreateScoringStrategies < ActiveRecord::Migration[8.1]
  def change
    create_enum :strategy_status, %w[draft published retired]

    create_table :scoring_strategies do |t|
      t.string :name, null: false
      t.string :version_code, null: false
      t.enum :status, enum_type: :strategy_status, null: false, default: "draft"
      t.timestamp :effective_at, null: false
      t.timestamp :published_at
      t.jsonb :rules_json, null: false, default: {}
      t.text :change_note
      t.timestamps
    end

    add_index :scoring_strategies, :version_code, unique: true

    add_index :scoring_strategies, :effective_at,
              name: "idx_strategies_effective_at"

    # Deterministic uniqueness for published strategies: there can be at most
    # ONE published strategy at any given effective_at. Drafts are allowed to
    # share an effective_at because they are not yet selectable.
    execute <<~SQL
      CREATE UNIQUE INDEX idx_strategies_one_published_per_effective_at
      ON scoring_strategies (effective_at)
      WHERE status = 'published';
    SQL
  end
end
