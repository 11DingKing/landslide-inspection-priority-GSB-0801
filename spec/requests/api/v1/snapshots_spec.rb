require "rails_helper"

RSpec.describe "Api::V1::Snapshots", type: :request do
  let!(:v1) { create(:scoring_strategy, version: 1, effective_at: 2.weeks.ago) }

  describe "GET /api/v1/snapshots/:id" do
    it "returns an immutable snapshot with breakdown and version" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      snapshot = PriorityCalculator.call(point).snapshot

      get "/api/v1/snapshots/#{snapshot.id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["immutable"]).to be(true)
      expect(body["scoring"]["strategy_version"]).to eq(1)
      expect(body["scoring"]["total_score"]).to eq(95)
    end
  end

  describe "POST /api/v1/snapshots/:id/replay" do
    it "recomputes the snapshot under a different strategy version" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      original = PriorityCalculator.call(point, strategy_version: v1.version).snapshot

      v2_rules = ScoringRules::V1.rules.dup
      v2_rules["items"] = v2_rules["items"].map do |item|
        item["key"] == "rainfall_24h" ? item.merge("max" => 100,
          "tiers" => [{ "min" => 0, "max" => nil, "score" => 100 }]) : item
      end
      v2 = create(:scoring_strategy, version: 2, effective_at: 1.day.ago, rules: v2_rules)

      post "/api/v1/snapshots/#{original.id}/replay",
           params: { strategy_version: 2 }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["scoring"]["strategy_version"]).to eq(2)
      expect(body["id"]).not_to eq(original.id)
      expect(body["evidence"]["rainfall_24h_mm"]).to eq(186.0)
      expect(body["scoring"]["total_score"]).to be > original.total_score

      get "/api/v1/snapshots/#{original.id}"
      expect(JSON.parse(response.body)["scoring"]["total_score"]).to eq(95)
    end
  end
end
