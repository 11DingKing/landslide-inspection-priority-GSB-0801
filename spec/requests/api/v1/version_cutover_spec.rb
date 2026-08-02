require "rails_helper"

RSpec.describe "Strategy version cutover and RDS-002", type: :request do
  let(:v1_start) { Time.utc(2026, 1, 1, 0, 0, 0) }
  let(:boundary) { Time.utc(2026, 8, 2, 0, 0, 0) }
  let!(:v1) do
    create(:scoring_strategy, version: 1, effective_at: v1_start,
           name: "v1", rules: ScoringRules::V1.rules)
  end
  let!(:v2) do
    create(:scoring_strategy, version: 2, effective_at: boundary,
           name: "v2", rules: ScoringRules::V2.rules)
  end

  describe "StrategyResolver" do
    it "resolves v1 before the boundary and v2 at/after the boundary" do
      expect(StrategyResolver.resolve(boundary - 1).version).to eq(1)
      expect(StrategyResolver.resolve(boundary).version).to eq(2)
      expect(StrategyResolver.resolve(boundary + 1).version).to eq(2)
    end
  end

  describe "snapshot version binding" do
    it "binds pre-boundary snapshots to v1 and boundary snapshots to v2" do
      point = create(:hazard_point, point_type: "road_slope", road_accessible: false,
                     latest_rainfall_24h_mm: 112.0, historical_event_count: 0,
                     last_inspected_at: 2.days.ago)

      before = PriorityCalculator.call(point, at: boundary - 1).snapshot
      at_boundary = PriorityCalculator.call(point, at: boundary,
                                            rainfall_24h_mm: 210.0).snapshot

      expect(before.strategy_version).to eq(1)
      expect(at_boundary.strategy_version).to eq(2)
    end

    it "keeps v1 published so old snapshots remain replayable after v2 is active" do
      old_point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      old_snapshot = PriorityCalculator.call(old_point, at: boundary - 1).snapshot

      expect(old_snapshot.strategy_version).to eq(1)
      expect(StrategyResolver.find_version(1).status).to eq("published")

      replayed = PriorityCalculator.replay(old_snapshot, strategy_version: 2)
      expect(replayed.strategy_version).to eq(2)
      expect(replayed.rainfall_24h_mm.to_f).to eq(186.0)

      expect(old_snapshot.reload.strategy_version).to eq(1)
    end
  end

  describe "RDS-002 boundary snapshot" do
    let(:business_id) { "evidence-rds-002-20260802-0000" }

    let!(:rds002) do
      create(:hazard_point, name: "RDS-002", point_type: "road_slope",
             road_accessible: false, latest_rainfall_24h_mm: 210.0,
             historical_event_count: 0, last_inspected_at: nil)
    end

    it "binds to v2, scores 210mm rainfall at max, and stays blocked" do
      outcome = PriorityCalculator.call(
        rds002, at: boundary, rainfall_24h_mm: 210.0, business_id: business_id
      )
      snapshot = outcome.snapshot

      expect(outcome.created).to be(true)
      expect(snapshot.strategy_version).to eq(2)
      expect(snapshot.business_id).to eq(business_id)
      expect(snapshot.rainfall_24h_mm.to_f).to eq(210.0)
      expect(snapshot.road_status).to eq("closed")
      expect(snapshot.dispatch_status).to eq("blocked")
      expect(snapshot.total_score).not_to eq(0)

      rainfall_item = snapshot.score_breakdown.find { |i| i["key"] == "rainfall_24h" }
      expect(rainfall_item["score"]).to eq(rainfall_item["max"])
      expect(snapshot.score_breakdown.sum { |i| i["score"] }).to eq(snapshot.total_score)
    end

    it "is idempotent for the same business_id with identical payload" do
      first = PriorityCalculator.call(rds002, at: boundary, rainfall_24h_mm: 210.0,
                                             business_id: business_id)
      second = PriorityCalculator.call(rds002, at: boundary, rainfall_24h_mm: 210.0,
                                              business_id: business_id)

      expect(first.created).to be(true)
      expect(second.created).to be(false)
      expect(second.snapshot.id).to eq(first.snapshot.id)
      expect(EvidenceSnapshot.where(business_id: business_id).count).to eq(1)
    end

    it "conflicts when the same business_id is reused with different rainfall" do
      PriorityCalculator.call(rds002, at: boundary, rainfall_24h_mm: 210.0,
                                     business_id: business_id)

      expect {
        PriorityCalculator.call(rds002, at: boundary, rainfall_24h_mm: 180.0,
                                       business_id: business_id)
      }.to raise_error(PriorityCalculator::PayloadConflict)
    end

    it "exposes idempotent creation and conflict through the API" do
      post "/api/v1/hazard_points/#{rds002.id}/calculate_priority",
           params: { at: boundary.iso8601, rainfall_24h_mm: 210.0,
                     business_id: business_id }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["business_id"]).to eq(business_id)
      expect(JSON.parse(response.body)["scoring"]["strategy_version"]).to eq(2)

      post "/api/v1/hazard_points/#{rds002.id}/calculate_priority",
           params: { at: boundary.iso8601, rainfall_24h_mm: 210.0,
                     business_id: business_id }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:ok)

      post "/api/v1/hazard_points/#{rds002.id}/calculate_priority",
           params: { at: boundary.iso8601, rainfall_24h_mm: 180.0,
                     business_id: business_id }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:conflict)
    end
  end
end
