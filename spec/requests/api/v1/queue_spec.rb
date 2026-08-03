require "rails_helper"

RSpec.describe "Api::V1::Queue", type: :request do
  let!(:strategy) { create(:scoring_strategy, effective_at: 1.week.ago) }

  before do
    @critical = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
    @blocked = create(:hazard_point, :road_slope_closed)
    @low = create(:hazard_point, :registered_hazard, latest_rainfall_24h_mm: 10.0,
                                                     historical_event_count: 0,
                                                     last_inspected_at: Time.current)
    [@critical, @blocked, @low].each { |p| PriorityCalculator.call(p) }
  end

  describe "GET /api/v1/queue" do
    it "returns points ordered by descending score" do
      get "/api/v1/queue"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      scores = body["queue"].map { |i| i["total_score"] }
      expect(scores).to eq([95, 52, 8])
    end

    it "marks blocked points with dispatch_status blocked and preserves risk level" do
      get "/api/v1/queue"
      blocked = JSON.parse(response.body)["queue"].find { |i| i["dispatch_status"] == "blocked" }
      expect(blocked["total_score"]).to eq(52)
      expect(blocked["risk_level"]).to eq("medium")
      expect(blocked["road_status"]).to eq("closed")
    end

    it "excludes blocked points when include_blocked=false" do
      get "/api/v1/queue", params: { include_blocked: false }
      statuses = JSON.parse(response.body)["queue"].map { |i| i["dispatch_status"] }
      expect(statuses).not_to include("blocked")
    end

    it "paginates with a cursor without losing order" do
      get "/api/v1/queue", params: { limit: 2 }
      body = JSON.parse(response.body)
      expect(body["queue"].length).to eq(2)
      expect(body["meta"]["next_cursor"]).to be_present

      get "/api/v1/queue", params: { limit: 2, cursor: body["meta"]["next_cursor"] }
      second = JSON.parse(response.body)
      expect(second["queue"].length).to eq(1)
      expect(second["meta"]["next_cursor"]).to be_nil
    end
  end
end
