require "rails_helper"

RSpec.describe "Api::V1::Strategies", type: :request do
  describe "GET /api/v1/strategies" do
    it "lists strategies ordered by effectiveness" do
      create(:scoring_strategy, version: 1, effective_at: 3.days.ago)
      create(:scoring_strategy, version: 2, effective_at: 1.day.ago)

      get "/api/v1/strategies"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |s| s["version"] }).to eq([2, 1])
    end
  end

  describe "POST /api/v1/strategies" do
    it "creates a draft strategy" do
      attrs = {
        strategy: {
          name: "v2",
          effective_at: 1.day.from_now.iso8601,
          rules: ScoringRules::V1.rules
        }
      }
      post "/api/v1/strategies", params: attrs.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("draft")
    end

    it "rejects malformed rules" do
      attrs = { strategy: { name: "bad", effective_at: 1.day.from_now.iso8601, rules: { "items" => [] } } }
      post "/api/v1/strategies", params: attrs.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(422)
    end
  end

  describe "POST /api/v1/strategies/:id/publish" do
    it "publishes a draft" do
      strategy = create(:scoring_strategy, :draft, effective_at: 1.day.ago)
      post "/api/v1/strategies/#{strategy.id}/publish"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("published")
    end

    it "rejects a second published strategy at the same effective_at with 409" do
      time = 1.day.ago.beginning_of_day.iso8601
      create(:scoring_strategy, version: 1, effective_at: time)
      draft = create(:scoring_strategy, :draft, version: 2, effective_at: time)

      post "/api/v1/strategies/#{draft.id}/publish"
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["error"]).to eq("conflict")
    end
  end

  describe "GET /api/v1/strategies/active" do
    it "returns the strategy effective at a given time" do
      create(:scoring_strategy, version: 1, effective_at: 5.days.ago)
      create(:scoring_strategy, version: 2, effective_at: 1.day.ago)

      get "/api/v1/strategies/active", params: { at: 2.days.ago.iso8601 }
      expect(JSON.parse(response.body)["version"]).to eq(1)

      get "/api/v1/strategies/active"
      expect(JSON.parse(response.body)["version"]).to eq(2)
    end
  end
end
