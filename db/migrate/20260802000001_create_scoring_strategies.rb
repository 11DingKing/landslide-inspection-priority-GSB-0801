class CreateScoringStrategies < ActiveRecord::Migration[8.1]
  def change
    create_table :scoring_strategies do |t|
      t.integer :version, null: false
      t.string :name, null: false
      t.text :description
      t.datetime :effective_at, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :rules, null: false

      t.timestamps
    end

    add_index :scoring_strategies, :version, unique: true
    add_index :scoring_strategies, [:status, :effective_at]

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE UNIQUE INDEX index_scoring_strategies_on_published_effective_at
          ON scoring_strategies (effective_at)
          WHERE status = 'published';
        SQL
      end
      dir.down do
        execute <<~SQL
          DROP INDEX IF EXISTS index_scoring_strategies_on_published_effective_at;
        SQL
      end
    end
  end
end
