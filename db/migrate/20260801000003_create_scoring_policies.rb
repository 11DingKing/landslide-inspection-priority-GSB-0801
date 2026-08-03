class CreateScoringPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :scoring_policies do |t|
      t.string :version, null: false
      t.string :status, null: false, default: "draft"

      # effective_at is the instant this policy becomes authoritative. A snapshot
      # is scored by the published policy with the greatest effective_at that is
      # <= captured_at, giving a single deterministic winner per snapshot.
      t.datetime :effective_at, null: false

      # Declarative rule definition consumed only by Scoring::Engine. Weights,
      # thresholds and curves live here so scoring is versioned data, not code
      # scattered across controllers or callbacks.
      t.jsonb :definition, null: false, default: {}

      t.datetime :published_at

      t.timestamps
    end

    add_index :scoring_policies, :version, unique: true
    add_index :scoring_policies, :status

    # Overlap rejection: at most one PUBLISHED policy may claim any given
    # effective_at instant. A concurrent attempt to publish a second candidate
    # at the same instant fails on this unique index, so the "one authoritative
    # version" rule is enforced by the database, not by application timing.
    add_index :scoring_policies, :effective_at,
              unique: true,
              where: "status = 'published'",
              name: "index_published_policies_on_effective_at"

    add_check_constraint :scoring_policies,
                         "status IN ('draft', 'published', 'archived')",
                         name: "scoring_policies_status_check"
  end
end
