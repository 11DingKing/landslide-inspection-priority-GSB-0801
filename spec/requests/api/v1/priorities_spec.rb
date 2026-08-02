require "rails_helper"

RSpec.describe "Api::V1::Priorities", type: :request do
  let!(:strategy) { create(:scoring_strategy, effective_at: 1.week.ago) }

  describe "POST /api/v1/hazard_points/:id/calculate_priority" do
    it "computes and returns a priority with breakdown and rule version" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)

      post "/api/v1/hazard_points/#{point.id}/calculate_priority"
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body["scoring"]["total_score"]).to eq(95)
      expect(body["scoring"]["risk_level"]).to eq("critical")
      expect(body["scoring"]["dispatch_status"]).to eq("schedulable")
      expect(body["scoring"]["strategy_version"]).to eq(strategy.version)

      sum = body["scoring"]["score_breakdown"].sum { |i| i["score"] }
      expect(sum).to eq(body["scoring"]["total_score"])
      expect(body["explanation"]["sum_check"]).to eq(95)
    end

    it "returns blocked dispatch status but preserves risk when road is closed" do
      point = create(:hazard_point, :road_slope_closed)

      post "/api/v1/hazard_points/#{point.id}/calculate_priority"
      body = JSON.parse(response.body)
      expect(body["scoring"]["total_score"]).to eq(52)
      expect(body["scoring"]["risk_level"]).to eq("medium")
      expect(body["scoring"]["dispatch_status"]).to eq("blocked")
    end

    it "accepts a rainfall override" do
      point = create(:hazard_point, :registered_hazard, last_inspected_at: Time.current)

      post "/api/v1/hazard_points/#{point.id}/calculate_priority",
           params: { rainfall_24h_mm: 250 }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      body = JSON.parse(response.body)
      expect(body["evidence"]["rainfall_24h_mm"]).to eq(250.0)
      expect(body["scoring"]["total_score"]).to eq(60)
    end
  end

  describe "GET /api/v1/hazard_points/:id/priority" do
    it "returns the latest snapshot" do
      point = create(:hazard_point, :registered_hazard, last_inspected_at: Time.current)
      snapshot = PriorityCalculator.call(point).snapshot

      get "/api/v1/hazard_points/#{point.id}/priority"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(snapshot.id)
    end

    it "returns 404 when no snapshot exists" do
      point = create(:hazard_point)
      get "/api/v1/hazard_points/#{point.id}/priority"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/hazard_points/:id/priority_explanation" do
    it "returns the explanation whose item sum equals total" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      snapshot = PriorityCalculator.call(point).snapshot

      get "/api/v1/hazard_points/#{point.id}/priority_explanation"
      body = JSON.parse(response.body)
      expect(body["total_score"]).to eq(body["sum_of_items"])
      expect(body["strategy_version"]).to eq(strategy.version)
      expect(body["explanation"]["summary"]).to be_present
    end
  end
end
