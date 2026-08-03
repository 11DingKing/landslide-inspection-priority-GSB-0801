require "test_helper"

# The queue-read snapshot scenario: build queue-20260802-01 pinned to round-2
# (v2), read page 1, then write new evidence + recompute for RDS-002 and a same-
# score point, then continue paging on the ORIGINAL cursor. The pinned traversal
# must stay fixed on the frozen snapshot — no missed or duplicated items — while
# a fresh snapshot sees the updates, and old score explanations still replay by
# the v1/v2 boundary.
class QueueSnapshotStabilityTest < ActiveSupport::TestCase
  setup do
    @v1 = create_policy!(version: "qs-v1", effective_from: Time.utc(2026, 1, 1),
                         effective_until: Time.utc(2026, 8, 2))
    @v2 = create_policy!(version: "qs-v2", effective_from: Time.utc(2026, 8, 2))

    # Build a set of v2 `current` scores. Several points deliberately share a
    # score so page boundaries land inside a tie group.
    @points = {}
    # code => [total_target, rainfall to hit it via road_slope exposure]
    # We drive totals directly through rainfall + fixed exposure for road_slope.
    seed_specs = [
      ["RDS-002", 210], # -> 40 rainfall + 12 exposure + recency ...
      ["P-A", 210],
      ["P-B", 150],
      ["P-C", 150],
      ["P-D", 120],
      ["P-E", 95]
    ]
    seed_specs.each do |code, rainfall|
      pt = create_point!(code: code, category: "road_slope")
      snap = create_snapshot!(pt, captured_at: Time.utc(2026, 8, 2), rainfall: rainfall,
                              road_accessible: (code != "RDS-002"), last_inspected_at: Time.utc(2025, 6, 1))
      Scoring::Materializer.new(snap).call(policy: @v2)
      @points[code] = pt
    end
  end

  def all_current_ordered
    PriorityScore.where(scoring_policy_id: @v2.id, current: true)
                 .order(total_score: :desc, hazard_point_id: :asc)
                 .to_a
  end

  test "pinned traversal is stable across mid-read recompute: no miss, no dup" do
    snapshot = Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-01").call
    expected_ids = snapshot.items.keyset_ordered.map(&:hazard_point_id)
    assert_operator expected_ids.size, :>=, 6

    reader = Scoring::QueueSnapshotReader.new(snapshot)

    # Page 1.
    page1 = reader.page(limit: 3)
    seen = page1.records.map(&:hazard_point_id)
    assert_equal 3, seen.size
    cursor = page1.next_cursor
    refute_nil cursor

    # --- Mid-traversal disturbance ---
    # New evidence + recompute for RDS-002 (moves its live current up) and for a
    # same-score point (P-A). These change live `current` scores but must NOT
    # affect the frozen snapshot traversal.
    rds = @points["RDS-002"]
    rds_new = create_snapshot!(rds, captured_at: Time.utc(2026, 8, 3), rainfall: 300,
                               road_accessible: false, last_inspected_at: Time.utc(2025, 6, 1))
    Scoring::Materializer.new(rds_new).call(policy: @v2)

    pa = @points["P-A"]
    pa_new = create_snapshot!(pa, captured_at: Time.utc(2026, 8, 3), rainfall: 50,
                              road_accessible: true, last_inspected_at: Time.utc(2026, 8, 3))
    Scoring::Materializer.new(pa_new).call(policy: @v2)

    # Continue paging on the ORIGINAL cursor.
    while cursor
      pg = reader.page(limit: 3, cursor: cursor)
      seen.concat(pg.records.map(&:hazard_point_id))
      cursor = pg.next_cursor
    end

    # Full coverage of the frozen membership, in frozen order, with no dupes.
    assert_equal expected_ids, seen
    assert_equal seen.uniq, seen, "duplicate items across pages"
  end

  test "a NEW snapshot sees the updated results" do
    old_snapshot = Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-01").call
    old_rds_total = old_snapshot.items.find_by(hazard_point_id: @points["RDS-002"].id).total_score

    # Update RDS-002 with heavier rainfall and recompute.
    rds = @points["RDS-002"]
    rds_new = create_snapshot!(rds, captured_at: Time.utc(2026, 8, 3), rainfall: 300,
                               road_accessible: false, last_inspected_at: Time.utc(2025, 6, 1))
    new_score = Scoring::Materializer.new(rds_new).call(policy: @v2).priority_score

    new_snapshot = Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-02").call
    new_rds_item = new_snapshot.items.find_by(hazard_point_id: rds.id)

    assert_equal new_score.total_score, new_rds_item.total_score
    assert_operator new_rds_item.total_score, :>=, old_rds_total
    # The old frozen snapshot is unchanged.
    assert_equal old_rds_total,
                 old_snapshot.items.find_by(hazard_point_id: rds.id).total_score
  end

  test "frozen item still points at a score explainable by the v1/v2 boundary" do
    # Give RDS-002 an OLD (v1) score too, then confirm the v2 snapshot item's
    # score explains under v2 while the v1 score still explains under v1.
    rds = @points["RDS-002"]
    old_snap = create_snapshot!(rds, captured_at: Time.utc(2026, 7, 10), rainfall: 112,
                                road_accessible: false, last_inspected_at: Time.utc(2025, 6, 1))
    v1_score = Scoring::Materializer.new(old_snap).call(policy: @v1).priority_score

    snapshot = Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-01").call
    item = snapshot.items.find_by(hazard_point_id: rds.id)

    v2_explanation = Scoring::Presenter.explanation(PriorityScore.find(item.priority_score_id))
    v1_explanation = Scoring::Presenter.explanation(v1_score)

    assert_equal "qs-v2", v2_explanation.dig(:scoring_policy, :version)
    assert_equal "qs-v1", v1_explanation.dig(:scoring_policy, :version)
    # Both explanations honour the exact-sum invariant.
    assert_equal v2_explanation[:total_score], v2_explanation[:components_sum]
    assert_equal v1_explanation[:total_score], v1_explanation[:components_sum]
  end

  test "queue snapshots and their items are immutable" do
    snapshot = Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-01").call
    snapshot.name = "renamed"
    assert_raises(ActiveRecord::RecordNotSaved) { snapshot.save! }

    item = snapshot.items.first
    item.total_score = 999
    assert_raises(ActiveRecord::RecordNotSaved) { item.save! }
  end

  test "duplicate snapshot name is rejected" do
    Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-01").call
    assert_raises(ActiveRecord::RecordInvalid) do
      Scoring::QueueSnapshotBuilder.new(policy: @v2, name: "queue-20260802-01").call
    end
  end
end
