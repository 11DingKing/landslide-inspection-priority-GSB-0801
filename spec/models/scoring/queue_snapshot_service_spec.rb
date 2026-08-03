require "rails_helper"

RSpec.describe Scoring::QueueSnapshotService do
  let(:boundary) { Time.utc(2026, 8, 2, 0, 0, 0) }
  let(:v1) do
    create(:scoring_strategy, version_code: "v1.0-baseline",
                               effective_at: Time.utc(2026, 1, 1),
                               published_at: Time.utc(2026, 1, 1))
  end
  let(:v2) do
    create(:scoring_strategy, version_code: "v2.0-refined",
                               effective_at: boundary,
                               published_at: boundary)
  end

  def make_point(kind:, rain:, history:, last_inspected:, blocked: false, time:)
    point = create(:hazard_point, kind: kind, road_accessible: !blocked)
    snap = create(:evidence_snapshot,
                  hazard_point: point,
                  snapshot_time: time,
                  rainfall_24h_mm: rain,
                  historical_event_count: history,
                  last_inspected_at: last_inspected,
                  road_accessible: !blocked)
    Scoring::PriorityComputer.call(snap, now: time + 1)
    point
  end

  before do
    v1
    v2
    # 5 points at the boundary, all bound to v2 (snapshot_time >= boundary)
    @points = 5.times.map do |i|
      make_point(kind: "registered_hazard",
                 rain: [50, 95, 150, 200, 112][i],
                 history: i,
                 last_inspected: boundary - (i + 1) * 10.hours,
                 time: boundary + i * 60)
    end
  end

  it "freezes the queue order and paginates stably without misses or duplicates" do
    snapshot = described_class.create(name: "queue-20260802-01", snapshot_at: boundary + 1)
    expect(snapshot.total_count).to eq(5)
    expect(snapshot.scoring_strategy_id).to eq(v2.id)

    all_ids = []

    # Page 1
    page1 = described_class.page(snapshot, per_page: 2)
    expect(page1[:items].size).to eq(2)
    expect(page1[:has_more]).to be true
    all_ids.concat(page1[:items].map(&:hazard_point_id))
    cursor = page1[:next_cursor]

    # Now insert a NEW high-score point and recompute. This would shift the
    # live queue order, but the snapshot must remain frozen.
    new_point = make_point(kind: "cut_slope_building", rain: 200, history: 5,
                           last_inspected: nil, blocked: false,
                           time: boundary + 100)

    # Also recompute an existing point with new evidence (different score).
    existing = @points[2]
    new_snap = create(:evidence_snapshot,
                      hazard_point: existing,
                      snapshot_time: boundary + 200,
                      rainfall_24h_mm: 10,
                      historical_event_count: 0,
                      last_inspected_at: Time.current,
                      road_accessible: true)
    Scoring::PriorityComputer.call(new_snap, now: boundary + 201)

    # Page 2 using the original cursor from page 1
    page2 = described_class.page(snapshot, per_page: 2, cursor: cursor)
    expect(page2[:items].size).to eq(2)
    all_ids.concat(page2[:items].map(&:hazard_point_id))
    cursor = page2[:next_cursor]

    # Page 3 (last)
    page3 = described_class.page(snapshot, per_page: 2, cursor: cursor)
    expect(page3[:items].size).to eq(1)
    expect(page3[:has_more]).to be false
    all_ids.concat(page3[:items].map(&:hazard_point_id))

    # Exactly the original 5 points, no misses, no duplicates, and the new
    # point does NOT appear.
    expect(all_ids.uniq.size).to eq(5)
    expect(all_ids.size).to eq(5)
    expect(all_ids).to match_array(@points.map(&:id))
    expect(all_ids).not_to include(new_point.id)

    # Items are ordered by total_score DESC (frozen order)
    scores = [page1, page2, page3].flat_map { |p| p[:items].map(&:total_score) }
    expect(scores).to eq(scores.sort.reverse)
  end

  it "a NEW snapshot sees the updated scores but old snapshot remains unchanged" do
    old_snapshot = described_class.create(name: "queue-old", snapshot_at: boundary + 1)
    old_order = old_snapshot.items.ordered.map(&:hazard_point_id)

    # Insert new point
    new_point = make_point(kind: "cut_slope_building", rain: 200, history: 5,
                           last_inspected: nil, time: boundary + 100)

    new_snapshot = described_class.create(name: "queue-new", snapshot_at: boundary + 200)
    new_order = new_snapshot.items.ordered.map(&:hazard_point_id)

    # Old snapshot still has exactly 5 original points
    expect(old_order.size).to eq(5)
    expect(old_order).not_to include(new_point.id)

    # New snapshot includes the new point and has 6 total
    expect(new_order.size).to eq(6)
    expect(new_order).to include(new_point.id)
    # New point should be first (highest score)
    expect(new_order.first).to eq(new_point.id)
  end

  it "binds to the specified strategy when given one explicitly" do
    # v1 snapshot using an earlier time
    old_snap = create(:evidence_snapshot,
                      hazard_point: create(:hazard_point, :cut_slope),
                      snapshot_time: boundary - 1.day,
                      rainfall_24h_mm: 186,
                      historical_event_count: 2,
                      last_inspected_at: nil,
                      road_accessible: true)
    old_score = Scoring::PriorityComputer.call(old_snap, now: boundary - 23.hours)
    expect(old_score.scoring_strategy_id).to eq(v1.id)

    snapshot = described_class.create(name: "v1-snapshot", strategy: v1,
                                      snapshot_at: boundary - 1.day)
    expect(snapshot.scoring_strategy_id).to eq(v1.id)
    expect(snapshot.items.first.priority_score_id).to eq(old_score.id)
  end

  it "keeps old priority scores replayable by v1/v2 boundary" do
    old_snap = create(:evidence_snapshot,
                      hazard_point: create(:hazard_point, :road_slope, :blocked),
                      snapshot_time: boundary - 6.hours,
                      rainfall_24h_mm: 112,
                      historical_event_count: 0,
                      last_inspected_at: boundary - 70.hours,
                      road_accessible: false)
    old_score = Scoring::PriorityComputer.call(old_snap, now: boundary - 5.hours)
    expect(old_score.scoring_strategy.version_code).to eq("v1.0-baseline")

    boundary_snap = create(:evidence_snapshot,
                           hazard_point: old_snap.hazard_point,
                           snapshot_time: boundary,
                           rainfall_24h_mm: 210,
                           historical_event_count: 0,
                           last_inspected_at: boundary - 70.hours,
                           road_accessible: false,
                           business_key: "rds-boundary-test")
    new_score = Scoring::PriorityComputer.call(boundary_snap, now: boundary + 1)
    expect(new_score.scoring_strategy.version_code).to eq("v2.0-refined")

    # Old score still exists and is replayable
    expect(PriorityScore.find(old_score.id).explanation["version_code"]).to eq("v1.0-baseline")
    # Blocked status preserved in both
    expect(old_score.dispatch_status).to eq("blocked")
    expect(new_score.dispatch_status).to eq("blocked")
    # Different scores
    expect(new_score.total_score).not_to eq(old_score.total_score)
  end

  it "rejects duplicate snapshot names" do
    described_class.create(name: "unique-name", snapshot_at: boundary)
    expect {
      described_class.create(name: "unique-name", snapshot_at: boundary)
    }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
