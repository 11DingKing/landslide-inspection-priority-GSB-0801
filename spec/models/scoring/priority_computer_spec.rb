require "rails_helper"
require "concurrent"

RSpec.describe Scoring::PriorityComputer do
  let!(:strategy) { create(:scoring_strategy) }
  let(:point) { create(:hazard_point, :cut_slope) }
  let(:snapshot) do
    create(:evidence_snapshot,
           hazard_point: point, rainfall_24h_mm: 186,
           historical_event_count: 2, last_inspected_at: nil)
  end

  it "persists a PriorityScore whose components sum exactly to total" do
    score = described_class.call(snapshot, now: Time.current)
    sum = score.components.sum { |c| c["score"] }
    expect(sum).to eq(score.total_score)
    expect(score.total_score).to eq(96)
    expect(score.risk_level).to eq("critical")
  end

  it "freezes snapshot_time into the row" do
    score = described_class.call(snapshot, now: Time.current)
    expect(score.snapshot_time).to eq(snapshot.snapshot_time)
    expect(score.components).to all(include("name", "score", "max_score", "reason"))
  end

  it "is idempotent: recomputing the same pair returns the SAME row" do
    first  = described_class.call(snapshot, now: Time.current)
    second = described_class.call(snapshot, now: 1.hour.from_now)
    expect(second.id).to eq(first.id)
    expect(PriorityScore.count).to eq(1)
  end

  it "handles concurrent computation of the same (snapshot, strategy) pair" do
    # Use separate connections to truly exercise the UNIQUE index.
    threads = 8.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.call(EvidenceSnapshot.find(snapshot.id), now: Time.current)
        end
      end
    end
    rows = threads.map(&:value)
    ids = rows.map(&:id).uniq
    expect(ids.size).to eq(1)
    expect(PriorityScore.count).to eq(1)
  end

  it "can replay an old snapshot against a newer strategy version" do
    old_strategy = strategy
    new_rules = Scoring::Rules.default.to_h.tap do |h|
      h["point_type_weights"]["cut_slope_building"] = 5
    end
    new_strategy = create(:scoring_strategy,
                          version_code: "v2-stricter",
                          effective_at: 1.day.ago,
                          rules_json: new_rules)

    old_score = described_class.call(snapshot, strategy: old_strategy, now: Time.current)
    new_score = described_class.call(snapshot, strategy: new_strategy, now: Time.current)

    expect(old_score.id).not_to eq(new_score.id)
    expect(new_score.total_score).to be < old_score.total_score
    expect(new_score.explanation["version_code"]).to eq("v2-stricter")
    expect(old_score.explanation["version_code"]).to eq(old_strategy.version_code)
    # The original row is never silently overwritten.
    expect(PriorityScore.count).to eq(2)
  end

  it "does not reduce total_score when the road is blocked; only dispatch_status changes" do
    blocked_point = create(:hazard_point, :road_slope, :blocked)
    snap = create(:evidence_snapshot, hazard_point: blocked_point,
                                      rainfall_24h_mm: 112,
                                      last_inspected_at: 70.hours.ago)
    score = described_class.call(snap, now: Time.current)
    expect(score.total_score).to eq(50)
    expect(score.risk_level).to eq("medium")
    expect(score.dispatch_status).to eq("blocked")
    expect(score.road_accessible).to be false
  end
end
