class ConvertPoliciesToValidityIntervals < ActiveRecord::Migration[8.1]
  # Moves scoring policies from a single "effective instant" to a half-open
  # validity interval [effective_from, effective_until). This lets an existing
  # published policy be *bounded* (given an end) rather than retired, so any
  # snapshot captured inside its original window still resolves to it and
  # remains replayable.
  def up
    rename_column :scoring_policies, :effective_at, :effective_from
    add_column :scoring_policies, :effective_until, :datetime, null: true

    # The old "one published policy per instant" index is superseded by an
    # interval-overlap exclusion below.
    remove_index :scoring_policies, name: "index_published_policies_on_effective_at"

    add_check_constraint :scoring_policies,
                         "effective_until IS NULL OR effective_until > effective_from",
                         name: "scoring_policies_interval_order_check"

    # Overlap rejection at the interval level: no two PUBLISHED policies may have
    # overlapping [from, until) windows (NULL until = open-ended +infinity).
    # A concurrent publish that would overlap fails on this GiST exclusion
    # constraint, preserving a single authoritative policy per instant. The
    # two-argument tsrange defaults to '[)' and is IMMUTABLE over the
    # `timestamp without time zone` columns Rails creates (required for an index
    # expression); range GiST operator classes are built in.
    execute <<~SQL
      ALTER TABLE scoring_policies
        ADD CONSTRAINT scoring_policies_no_overlapping_published
        EXCLUDE USING gist (
          tsrange(effective_from, effective_until) WITH &&
        )
        WHERE (status = 'published');
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE scoring_policies
        DROP CONSTRAINT IF EXISTS scoring_policies_no_overlapping_published;
    SQL
    remove_check_constraint :scoring_policies,
                            name: "scoring_policies_interval_order_check"
    remove_column :scoring_policies, :effective_until
    rename_column :scoring_policies, :effective_from, :effective_at
    add_index :scoring_policies, :effective_at,
              unique: true,
              where: "status = 'published'",
              name: "index_published_policies_on_effective_at"
  end
end
