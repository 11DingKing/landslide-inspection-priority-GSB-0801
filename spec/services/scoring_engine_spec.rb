require "rails_helper"

RSpec.describe ScoringEngine do
  let(:strategy) { build(:scoring_strategy, rules: ScoringRules::V1.rules) }
  subject(:engine) { described_class.new(strategy) }

  let(:base_evidence) do
    {
      rainfall_24h_mm: 50.0,
      historical_event_count: 0,
      point_type: "registered_hazard",
      road_status: "accessible",
      last_inspected_at: Time.current,
      snapshot_at: Time.current
    }
  end

  def score(overrides = {})
    engine.score(base_evidence.merge(overrides))
  end

  describe "#score" do
    it "returns a result with itemized breakdown and total" do
      result = score
      expect(result.total_score).to eq(result.score_breakdown.sum { |i| i[:score] })
      expect(result.score_breakdown.map { |i| i[:key] }).to match_array(
        %w[rainfall_24h historical_events point_type_risk inspection_recency]
      )
    end

    it "locks every item score within 0..max" do
      result = score(rainfall_24h_mm: 9999)
      result.score_breakdown.each do |item|
        expect(item[:score]).to be_between(0, item[:max])
      end
    end

    it "strictly equals the sum of item scores" do
      [0, 49.9, 50, 99.9, 100, 149.9, 150, 186, 200, 300].each do |rain|
        result = score(rainfall_24h_mm: rain)
        sum = result.score_breakdown.sum { |i| i[:score] }
        expect(result.total_score).to eq(sum),
          "rainfall=#{rain}: total #{result.total_score} != sum #{sum}"
      end
    end

    it "records the strategy version on the explanation" do
      result = score
      expect(result.explanation["strategy_version"]).to eq(strategy.version)
    end

    describe "rainfall tiers" do
      it "scores 0 for [0,50)" do
        expect(score(rainfall_24h_mm: 0).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(0)
        expect(score(rainfall_24h_mm: 49.9).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(0)
      end

      it "scores 10 for [50,100)" do
        expect(score(rainfall_24h_mm: 50).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(10)
        expect(score(rainfall_24h_mm: 99.9).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(10)
      end

      it "scores 25 for [100,150)" do
        expect(score(rainfall_24h_mm: 112).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(25)
      end

      it "scores 35 for [150,200)" do
        expect(score(rainfall_24h_mm: 186).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(35)
      end

      it "scores 40 for >=200" do
        expect(score(rainfall_24h_mm: 200).score_breakdown.find { |i| i[:key] == "rainfall_24h" }[:score]).to eq(40)
      end
    end

    describe "historical events" do
      it "scores 0 for zero events" do
        expect(score(historical_event_count: 0).score_breakdown.find { |i| i[:key] == "historical_events" }[:score]).to eq(0)
      end

      it "scores 12 for one event" do
        expect(score(historical_event_count: 1).score_breakdown.find { |i| i[:key] == "historical_events" }[:score]).to eq(12)
      end

      it "scores 25 for two or more events" do
        expect(score(historical_event_count: 2).score_breakdown.find { |i| i[:key] == "historical_events" }[:score]).to eq(25)
        expect(score(historical_event_count: 5).score_breakdown.find { |i| i[:key] == "historical_events" }[:score]).to eq(25)
      end
    end

    describe "point type" do
      it "scores cut_slope_building 20, road_slope 12, registered_hazard 8" do
        expect(score(point_type: "cut_slope_building").score_breakdown.find { |i| i[:key] == "point_type_risk" }[:score]).to eq(20)
        expect(score(point_type: "road_slope").score_breakdown.find { |i| i[:key] == "point_type_risk" }[:score]).to eq(12)
        expect(score(point_type: "registered_hazard").score_breakdown.find { |i| i[:key] == "point_type_risk" }[:score]).to eq(8)
      end
    end

    describe "inspection recency" do
      it "scores 15 when never inspected" do
        expect(score(last_inspected_at: nil).score_breakdown.find { |i| i[:key] == "inspection_recency" }[:score]).to eq(15)
      end

      it "scores 0 when inspected same day" do
        now = Time.current
        expect(score(last_inspected_at: now - 2.hours, snapshot_at: now).score_breakdown.find { |i| i[:key] == "inspection_recency" }[:score]).to eq(0)
      end

      it "scores 15 when inspected on an earlier day" do
        now = Time.current
        expect(score(last_inspected_at: now - 2.days, snapshot_at: now).score_breakdown.find { |i| i[:key] == "inspection_recency" }[:score]).to eq(15)
      end
    end

    describe "risk levels" do
      it "maps score ranges to low/medium/high/critical" do
        expect(score(rainfall_24h_mm: 0, historical_event_count: 0, point_type: "registered_hazard", last_inspected_at: Time.current).risk_level).to eq("low")
        expect(score(rainfall_24h_mm: 95, historical_event_count: 1, point_type: "registered_hazard", last_inspected_at: Time.current - 2.days).risk_level).to eq("medium")
        expect(score(rainfall_24h_mm: 112, historical_event_count: 2, point_type: "road_slope", last_inspected_at: nil).risk_level).to eq("high")
        expect(score(rainfall_24h_mm: 186, historical_event_count: 2, point_type: "cut_slope_building", last_inspected_at: nil).risk_level).to eq("critical")
      end
    end

    describe "road unreachable" do
      it "does not reduce the risk score to zero" do
        result = score(road_status: "closed",
                       rainfall_24h_mm: 112,
                       historical_event_count: 0,
                       point_type: "road_slope",
                       last_inspected_at: 2.days.ago)
        expect(result.total_score).to eq(52)
        expect(result.risk_level).to eq("medium")
      end

      it "marks dispatch_status as blocked while preserving risk_level" do
        result = score(road_status: "closed",
                       rainfall_24h_mm: 186,
                       historical_event_count: 2,
                       point_type: "cut_slope_building",
                       last_inspected_at: nil)
        expect(result.dispatch_status).to eq("blocked")
        expect(result.risk_level).to eq("critical")
        expect(result.explanation["summary"]).to include("blocked")
        expect(result.explanation["summary"]).to include("原始风险等级保留")
      end

      it "leaves schedulable points as schedulable" do
        result = score(road_status: "accessible")
        expect(result.dispatch_status).to eq("schedulable")
      end
    end

    describe "determinism" do
      it "produces identical results for identical evidence and strategy" do
        a = score(rainfall_24h_mm: 186, historical_event_count: 2, point_type: "cut_slope_building", last_inspected_at: nil)
        b = score(rainfall_24h_mm: 186, historical_event_count: 2, point_type: "cut_slope_building", last_inspected_at: nil)
        expect(a.total_score).to eq(b.total_score)
        expect(a.score_breakdown.map { |i| i[:score] }).to eq(b.score_breakdown.map { |i| i[:score] })
      end
    end
  end
end
