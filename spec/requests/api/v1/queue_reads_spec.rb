require "rails_helper"

RSpec.describe "Queue reads API", type: :request do
  let(:v1_start) { Time.utc(2026, 1, 1) }
  let(:boundary) { Time.utc(2026, 8, 2, 0, 0, 0) }
  let(:cutoff) { Time.utc(2026, 8, 2, 1, 0, 0) }
  let!(:v1) { create(:scoring_strategy, version: 1, effective_at: v1_start, rules: ScoringRules::V1.rules) }
  let!(:v2) { create(:scoring_strategy, version: 2, effective_at: boundary, rules: ScoringRules::V2.rules) }

  it "creates a queue read, pages it frozen, and a new read sees updates" do
    rds004 = create(:hazard_point, name: "RDS-004", point_type: "cut_slope_building",
                                   road_accessible: true, latest_rainfall_24h_mm: 186.0,
                                   historical_event_count: 2, last_inspected_at: nil)
    rds002 = create(:hazard_point, name: "RDS-002", point_type: "road_slope",
                                   road_accessible: false, latest_rainfall_24h_mm: 112.0,
                                   historical_event_count: 0, last_inspected_at: nil)
    rds003 = create(:hazard_point, name: "RDS-003", point_type: "road_slope",
                                   road_accessible: false, latest_rainfall_24h_mm: 112.0,
                                   historical_event_count: 0, last_inspected_at: nil)
    [rds004, rds002, rds003].each { |p| PriorityCalculator.call(p, at: boundary) }

    post "/api/v1/queue_reads",
         params: { business_id: "queue-20260802-01", at: cutoff.iso8601 }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:created)
    qr = JSON.parse(response.body)
    expect(qr["strategy_version"]).to eq(2)
    expect(qr["cutoff_at"]).to eq(cutoff.iso8601)

    get "/api/v1/queue", params: { queue_read: "queue-20260802-01", limit: 2 }
    expect(response).to have_http_status(:ok)
    page1 = JSON.parse(response.body)
    expect(page1["queue"].size).to eq(2)
    expect(page1["meta"]["queue_read"]["business_id"]).to eq("queue-20260802-01")
    frozen_ids = page1["queue"].map { |i| i["snapshot_id"] }
    cursor = page1["meta"]["next_cursor"]
    expect(frozen_ids.size).to eq(2)

    after_time = cutoff + 600
    rds002.update!(latest_rainfall_24h_mm: 210.0)
    post "/api/v1/hazard_points/#{rds002.id}/calculate_priority",
         params: { at: after_time.iso8601, rainfall_24h_mm: 210.0 }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    new_rds002 = JSON.parse(response.body)
    post "/api/v1/hazard_points/#{rds003.id}/calculate_priority",
         params: { at: after_time.iso8601, rainfall_24h_mm: 112.0 }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    new_rds003 = JSON.parse(response.body)

    get "/api/v1/queue", params: { queue_read: "queue-20260802-01", limit: 2, cursor: cursor }
    page2 = JSON.parse(response.body)
    expect(page2["queue"].size).to eq(1)
    expect(page2["meta"]["next_cursor"]).to be_nil
    page2_ids = page2["queue"].map { |i| i["snapshot_id"] }
    expect(page2_ids).not_to include(new_rds002["id"], new_rds003["id"])
    all_ids = frozen_ids + page2_ids
    expect(all_ids.uniq).to eq(all_ids)
    expect(page2["meta"]["total_count"]).to eq(3)

    post "/api/v1/queue_reads",
         params: { business_id: "queue-20260802-02", at: (after_time + 60).iso8601 }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    get "/api/v1/queue", params: { queue_read: "queue-20260802-02", limit: 10 }
    new_page = JSON.parse(response.body)
    new_ids = new_page["queue"].map { |i| i["snapshot_id"] }
    expect(new_ids).to include(new_rds002["id"], new_rds003["id"])
  end
end
