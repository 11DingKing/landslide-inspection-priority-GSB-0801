class AddBusinessKeyAndCurrentScore < ActiveRecord::Migration[8.1]
  # business_key: a caller-supplied stable identifier for a snapshot. Same key +
  # same payload is idempotent (returns the existing snapshot); same key with a
  # different payload is a conflict. The unique index enforces the "same key can
  # only mean one thing" rule; the digest column distinguishes idempotent from
  # conflicting re-submissions.
  def change
    add_column :evidence_snapshots, :business_key, :string, null: true
    add_index :evidence_snapshots, :business_key, unique: true

    # current: marks the single authoritative score per hazard point (the score
    # a scheduler should act on right now). Exactly one row per hazard_point may
    # be current; concurrent computation must converge to one winner.
    add_column :priority_scores, :current, :boolean, null: false, default: false
    add_index :priority_scores, :hazard_point_id,
              unique: true,
              where: "current",
              name: "index_priority_scores_one_current_per_point"
  end
end
