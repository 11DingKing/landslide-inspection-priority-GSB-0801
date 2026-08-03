require "rails_helper"

RSpec.describe Scoring::Calculator do
  let(:rules) { Scoring::Rules.default }
  let(:now) { Time.current }

  def calc(overrides)
    evidence = {
      rainfall_24h_mm: overrides.fetch(:rainfall_24h_mm, 50),
      historical_event_count: overrides.fetch(:historical_event_count, 0),
      last_inspected_at: overrides[:last_inspected_at],
      road_accessible: overrides.fetch(:road_accessible, true),
      kind: overrides.fetch(:kind, "registered_hazard")
    }
    described_class.call(evidence, rules: rules, rules_version: "test-v1", now: now)
  end

  def component(result, name)
    result.components.find { |c| c["name"] == name }
  end

  it "produces components whose scores sum exactly to total_score" do
    result = calc(rainfall_24h_mm: 186, historical_event_count: 2,
                  last_inspected_at: nil, kind: "cut_slope_building")
    component_sum = result.components.sum { |c| c["score"] }
    expect(component_sum).to eq(result.total_score)
    expect(result.total_score).to eq(96)
  end

  it "scores rainfall by the correct bucket" do
    expect(component(calc(rainfall_24h_mm: 200), "rainfall_24h")["score"]).to eq(40)
    expect(component(calc(rainfall_24h_mm: 186), "rainfall_24h")["score"]).to eq(40)
    expect(component(calc(rainfall_24h_mm: 150), "rainfall_24h")["score"]).to eq(40)
    expect(component(calc(rainfall_24h_mm: 149), "rainfall_24h")["score"]).to eq(30)
    expect(component(calc(rainfall_24h_mm: 112), "rainfall_24h")["score"]).to eq(30)
    expect(component(calc(rainfall_24h_mm: 95),  "rainfall_24h")["score"]).to eq(18)
    expect(component(calc(rainfall_24h_mm: 50),  "rainfall_24h")["score"]).to eq(18)
    expect(component(calc(rainfall_24h_mm: 49),  "rainfall_24h")["score"]).to eq(5)
  end

  it "caps historical events score" do
    r = calc(rainfall_24h_mm: 0, historical_event_count: 100)
    expect(component(r, "historical_events")["score"]).to eq(20)
  end

  it "treats never inspected as the highest recency score" do
    r = calc(rainfall_24h_mm: 0, last_inspected_at: nil)
    expect(component(r, "inspection_recency")["score"]).to eq(20)
  end

  it "scores same-day inspection as within_24h (0)" do
    r = calc(rainfall_24h_mm: 0, last_inspected_at: now - 6.hours)
    expect(component(r, "inspection_recency")["score"]).to eq(0)
  end

  it "scores an earlier inspection (70h) as within_72h (8)" do
    r = calc(rainfall_24h_mm: 0, last_inspected_at: now - 70.hours)
    expect(component(r, "inspection_recency")["score"]).to eq(8)
  end

  it "does NOT lower the score when the road is inaccessible" do
    open   = calc(rainfall_24h_mm: 112, kind: "road_slope",
                  road_accessible: true, last_inspected_at: now - 70.hours)
    closed = calc(rainfall_24h_mm: 112, kind: "road_slope",
                  road_accessible: false, last_inspected_at: now - 70.hours)
    expect(closed.total_score).to eq(open.total_score)
    expect(closed.risk_level).to eq(open.risk_level)
    expect(closed.risk_level).to eq("medium")
    expect(closed.dispatch_status).to eq("blocked")
    expect(open.dispatch_status).to eq("available")
  end

  it "is a pure function: identical inputs return identical outputs" do
    evidence = { rainfall_24h_mm: 186, historical_event_count: 2,
                 last_inspected_at: nil, road_accessible: true,
                 kind: "cut_slope_building" }
    a = described_class.call(evidence, rules: rules, rules_version: "v", now: now)
    b = described_class.call(evidence, rules: rules, rules_version: "v", now: now)
    expect(a.to_h).to eq(b.to_h)
  end

  it "classifies risk levels correctly for the three mandatory seed points" do
    cut = calc(rainfall_24h_mm: 186, historical_event_count: 2,
               last_inspected_at: nil, kind: "cut_slope_building")
    road = calc(rainfall_24h_mm: 112, historical_event_count: 0,
                last_inspected_at: now - 70.hours, kind: "road_slope")
    reg = calc(rainfall_24h_mm: 95, historical_event_count: 1,
               last_inspected_at: now - 6.hours, kind: "registered_hazard")
    expect(cut.risk_level).to eq("critical")
    expect(road.risk_level).to eq("medium")
    expect(reg.risk_level).to eq("low")
  end

  it "freezes the result so it cannot be mutated after the fact" do
    r = calc(rainfall_24h_mm: 50)
    expect { r.total_score = 999 }.to raise_error(FrozenError)
  end

  it "never exceeds the component max ranges" do
    50.times do
      r = calc(
        rainfall_24h_mm: rand(0..300),
        historical_event_count: rand(0..20),
        last_inspected_at: [nil, rand(0..200).hours.ago].sample,
        kind: %w[cut_slope_building road_slope registered_hazard].sample
      )
      r.components.each do |c|
        expect(c["score"]).to be <= c["max_score"]
        expect(c["score"]).to be >= 0
      end
      expect(r.total_score).to be <= 100
      expect(r.components.sum { |c| c["score"] }).to eq(r.total_score)
    end
  end
end
