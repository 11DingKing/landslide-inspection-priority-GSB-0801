require "rails_helper"

RSpec.describe "Queue snapshots API", type: :request do
  let(:boundary) { Time.utc(2026, 8, 2, 0, 0, 0) }
  let!(:v1) do
    create(:scoring_strategy, version_code: "v1.0-baseline",
                               effective_at: Time.utc(2026, 1, 1),
                               published_at: Time.utc(2026, 1, 1))
  end
  let!(:v2) do
    create(:scoring_strategy, version_code: "v2.0-refined",
                               effective_at: boundary,
                               published_at: boundary)
  end

  def make_point(kind:, rain:, history:, last_inspected:, blocked: false, time:, code: nil)
    point = create(:hazard_point, kind: kind, road_accessible: !blocked,
                                   external_code: code)
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
    @p1 = make_point(kind: "cut_slope_building", rain: 186, history: 2,
                     last_inspected: nil, time: boundary, code: "HCS-001")
    @rds = make_point(kind: "road_slope", rain: 112, history: 0,
                      last_inspected: boundary - 70.hours, blocked: true,
                      time: boundary, code: "RDS-002")
    @p3 = make_point(kind: "registered_hazard", rain: 95, history: 1,
                     last_inspected: boundary - 6.hours, time: boundary,
                     code: "HRG-001")
  end

  it "freezes a traversal against v2 and is unaffected by mid-walk writes" do
    # 1. Create snapshot queue-20260802-01
    post "/queue_snapshots", params: {
      name: "queue-20260802-01",
      snapshot_at: boundary.iso8601
    }
    expect(response).to have_http_status(:created)
    snap = JSON.parse(response.body)
    expect(snap["version_code"]).to eq("v2.0-refined")
    expect(snap["total_count"]).to eq(3)
    snapshot_id = snap["id"]

    # 2. Read page 1
    get "/queue_snapshots/#{snapshot_id}/items", params: { per_page: 1 }
    expect(response).to have_http_status(:ok)
    page1 = JSON.parse(response.body)
    expect(page1["items"].size).to eq(1)
    first_point_id = page1["items"].first["hazard_point_id"]
    expect(first_point_id).to eq(@p1.id)
    expect(page1["has_more"]).to be true
    cursor = page1["next_cursor"]

    # 3. Write new evidence for RDS-002 + a tie-score point, recompute
    #
    # RDS-002's original score was 50 (rain 112=>30, history 0, inspection
    # within_72h=>8, type road_slope=>12). The new evidence raises rainfall to
    # 210 (=>40) and, by scoring at boundary+4h (74h after the last inspection),
    # moves inspection into the "older" bucket (=>15), yielding 40+0+15+12 = 67.
    new_rds_snap = create(:evidence_snapshot,
                          hazard_point: @rds,
                          snapshot_time: boundary + 1.hour,
                          rainfall_24h_mm: 210,
                          historical_event_count: 0,
                          last_inspected_at: boundary - 70.hours,
                          road_accessible: false,
                          business_key: "evidence-rds-002-20260802-0100")
    Scoring::PriorityComputer.call(new_rds_snap, now: boundary + 4.hours)

    # A tie-score point: identical inputs to @p3 produce the same score (34),
    # exercising stable tie-breaking on the live queue.
    tie_point = make_point(kind: "registered_hazard", rain: 95, history: 1,
                           last_inspected: boundary - 6.hours,
                           time: boundary + 4.hours, code: "TIE-001")

    # 4. Continue paging with the ORIGINAL cursor — no misses, no duplicates
    get "/queue_snapshots/#{snapshot_id}/items",
        params: { per_page: 1, cursor: cursor }
    page2 = JSON.parse(response.body)
    expect(page2["items"].size).to eq(1)
    second_point_id = page2["items"].first["hazard_point_id"]
    expect(second_point_id).to eq(@rds.id)
    cursor = page2["next_cursor"]

    get "/queue_snapshots/#{snapshot_id}/items",
        params: { per_page: 1, cursor: cursor }
    page3 = JSON.parse(response.body)
    expect(page3["items"].size).to eq(1)
    expect(page3["has_more"]).to be false
    third_point_id = page3["items"].first["hazard_point_id"]
    expect(third_point_id).to eq(@p3.id)

    # The frozen snapshot still has exactly 3 items; tie point and new RDS
    # score do not appear.
    seen = [first_point_id, second_point_id, third_point_id]
    expect(seen.uniq.size).to eq(3)
    expect(seen).not_to include(tie_point.id)

    # 5. A NEW traversal sees the updated state
    post "/queue_snapshots", params: {
      name: "queue-20260802-02",
      snapshot_at: (boundary + 3.hours).iso8601
    }
    snap2 = JSON.parse(response.body)
    expect(snap2["total_count"]).to eq(4)

    get "/queue_snapshots/#{snap2['id']}/items", params: { per_page: 10 }
    items = JSON.parse(response.body)["items"]
    new_ids = items.map { |i| i["hazard_point_id"] }
    expect(new_ids).to include(tie_point.id)
    # RDS-002's new score (higher) moves it up
    rds_entry = items.find { |i| i["hazard_point_id"] == @rds.id }
    expect(rds_entry["total_score"]).to eq(67)
  end

  it "old priority scores remain replayable by v1/v2 boundary" do
    # Pre-boundary snapshot bound to v1
    pre_point = make_point(kind: "road_slope", rain: 112, history: 0,
                           last_inspected: boundary - 70.hours, blocked: true,
                           time: boundary - 6.hours, code: "RDS-OLD")
    pre_score = PriorityScore.where(hazard_point_id: pre_point.id).current.first
    expect(pre_score.scoring_strategy.version_code).to eq("v1.0-baseline")

    # Boundary snapshot bound to v2
    boundary_snap = create(:evidence_snapshot,
                           hazard_point: pre_point,
                           snapshot_time: boundary,
                           rainfall_24h_mm: 210,
                           historical_event_count: 0,
                           last_inspected_at: boundary - 70.hours,
                           road_accessible: false,
                           business_key: "rds-old-boundary")
    Scoring::PriorityComputer.call(boundary_snap, now: boundary + 1)

    # Both scores coexist
    scores = PriorityScore.where(hazard_point_id: pre_point.id).to_a
    expect(scores.size).to eq(2)
    versions = scores.map { |s| s.explanation["version_code"] }
    expect(versions).to contain_exactly("v1.0-baseline", "v2.0-refined")
    # Both blocked but risk preserved
    scores.each do |s|
      expect(s.dispatch_status).to eq("blocked")
      expect(s.components.sum { |c| c["score"] }).to eq(s.total_score)
    end

    # Explanation endpoint works for old v1 score
    get "/priority/#{pre_score.id}/explain"
    body = JSON.parse(response.body)
    expect(body["version_code"]).to eq("v1.0-baseline")
    expect(body["sum_matches_total"]).to be true
  end
end
