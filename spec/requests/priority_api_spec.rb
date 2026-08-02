require "rails_helper"

RSpec.describe "Priority API", type: :request do
  let!(:strategy) { create(:scoring_strategy, version_code: "v1.0") }

  let(:cut_slope_point) do
    create(:hazard_point, :cut_slope, name: "切坡建房点 A")
  end
  let(:road_slope_point) do
    create(:hazard_point, :road_slope, :blocked, name: "道路边坡点 B")
  end
  let(:registered_point) do
    create(:hazard_point, name: "登记隐患点 C")
  end

  def snapshot_for(point, rain:, history:, last_inspected:, time: Time.current)
    create(:evidence_snapshot,
           hazard_point: point, snapshot_time: time,
           rainfall_24h_mm: rain, historical_event_count: history,
           last_inspected_at: last_inspected,
           road_accessible: point.road_accessible)
  end

  before do
    snapshot_for(cut_slope_point, rain: 186, history: 2, last_inspected: nil)
    snapshot_for(road_slope_point, rain: 112, history: 0,
                                    last_inspected: 70.hours.ago)
    snapshot_for(registered_point, rain: 95, history: 1,
                                   last_inspected: 6.hours.ago)
  end

  describe "POST /hazard_points/:hp_id/evidence_snapshots/:id/priority" do
    it "returns components, total, risk level and rule version" do
      snap = cut_slope_point.evidence_snapshots.first
      post "/hazard_points/#{cut_slope_point.id}/evidence_snapshots/#{snap.id}/priority"
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["total_score"]).to eq(96)
      expect(body["version_code"]).to eq("v1.0")
      expect(body["risk_level"]).to eq("critical")
      component_sum = body["components"].sum { |c| c["score"] }
      expect(component_sum).to eq(body["total_score"])
      expect(body["components"].map { |c| c["name"] })
        .to match_array(%w[rainfall_24h historical_events inspection_recency point_type_weight])
    end

    it "does not zero out a blocked point; risk level is preserved" do
      snap = road_slope_point.evidence_snapshots.first
      post "/hazard_points/#{road_slope_point.id}/evidence_snapshots/#{snap.id}/priority"
      body = JSON.parse(response.body)
      expect(body["total_score"]).to eq(50)
      expect(body["risk_level"]).to eq("medium")
      expect(body["dispatch_status"]).to eq("blocked")
      expect(body["road_accessible"]).to be false
    end
  end

  describe "GET /priority/queue" do
    before do
      EvidenceSnapshot.find_each do |s|
        Scoring::PriorityComputer.call(s, now: Time.current)
      end
    end

    it "returns points ordered by total score desc" do
      get "/priority/queue"
      body = JSON.parse(response.body)
      scores = body["items"].map { |i| i["total_score"] }
      expect(scores).to eq(scores.sort.reverse)
      expect(body["total"]).to eq(3)
    end

    it "supports keyset cursor pagination" do
      get "/priority/queue", params: { per_page: 2 }
      body = JSON.parse(response.body)
      expect(body["items"].size).to eq(2)
      expect(body["has_more"]).to be true

      get "/priority/queue", params: { per_page: 2, cursor: body["next_cursor"] }
      page2 = JSON.parse(response.body)
      expect(page2["items"].size).to eq(1)
      expect(page2["has_more"]).to be false
    end
  end

  describe "GET /priority/:id/explain" do
    it "explains the score and verifies component sum invariant" do
      snap = cut_slope_point.evidence_snapshots.first
      score = Scoring::PriorityComputer.call(snap, now: Time.current)
      get "/priority/#{score.id}/explain"
      body = JSON.parse(response.body)
      expect(body["sum_matches_total"]).to be true
      expect(body["component_sum"]).to eq(body["total_score"])
      expect(body["version_code"]).to eq("v1.0")
      expect(body["snapshot_time"]).to be_present
    end
  end

  describe "POST /strategies" do
    it "rejects two published strategies at the same effective_at" do
      time = 2.days.ago.beginning_of_day
      post "/strategies", params: {
        strategy: {
          name: "A", version_code: "a-1", effective_at: time.iso8601,
          rules_json: Scoring::Rules.default.to_h
        }
      }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      a = JSON.parse(response.body)
      post "/strategies/#{a['id']}/publish"

      post "/strategies", params: {
        strategy: {
          name: "B", version_code: "b-1", effective_at: time.iso8601,
          rules_json: Scoring::Rules.default.to_h
        }
      }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      b = JSON.parse(response.body)
      post "/strategies/#{b['id']}/publish"
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "POST /priority/replay" do
    it "replays old snapshots against a new strategy version" do
      old_snap = cut_slope_point.evidence_snapshots.first
      old_score = Scoring::PriorityComputer.call(old_snap, now: Time.current)

      new_rules = Scoring::Rules.default.to_h
      new_rules["point_type_weights"]["cut_slope_building"] = 3
      new_strategy = create(:scoring_strategy,
                            version_code: "v2",
                            effective_at: 1.minute.ago,
                            rules_json: new_rules)

      post "/priority/replay", params: {
        strategy_id: new_strategy.id,
        snapshot_ids: [old_snap.id]
      }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      body = JSON.parse(response.body)
      replayed = body["items"].first
      expect(replayed["version_code"]).to eq("v2")
      expect(replayed["total_score"]).to be < old_score.total_score
    end
  end
end
