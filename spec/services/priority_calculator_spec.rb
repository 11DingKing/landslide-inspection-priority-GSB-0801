require "rails_helper"

RSpec.describe PriorityCalculator do
  let!(:strategy) { create(:scoring_strategy, effective_at: 1.week.ago) }

  describe ".call" do
    it "creates an immutable snapshot with itemized scores and strategy version" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      snapshot = described_class.call(point).snapshot

      expect(snapshot).to be_persisted
      expect(snapshot.strategy_version).to eq(strategy.version)
      expect(snapshot.total_score).to eq(95)
      expect(snapshot.risk_level).to eq("critical")
      expect(snapshot.dispatch_status).to eq("schedulable")
      expect(snapshot.score_breakdown.sum { |i| i["score"] }).to eq(95)
      expect(snapshot.snapshot_at).to be_present
    end

    it "preserves the original risk level and marks dispatch blocked when road is closed" do
      point = create(:hazard_point, :road_slope_closed)
      snapshot = described_class.call(point).snapshot

      expect(snapshot.total_score).to eq(52)
      expect(snapshot.total_score).not_to eq(0)
      expect(snapshot.risk_level).to eq("medium")
      expect(snapshot.dispatch_status).to eq("blocked")
      expect(snapshot.road_status).to eq("closed")
    end

    it "freezes raw evidence into the snapshot even if the point later changes" do
      point = create(:hazard_point, :registered_hazard, latest_rainfall_24h_mm: 95.0,
                                                       last_inspected_at: Time.current)
      snapshot = described_class.call(point, at: Time.current).snapshot

      point.update!(latest_rainfall_24h_mm: 300.0, historical_event_count: 9)

      expect(snapshot.reload.rainfall_24h_mm.to_f).to eq(95.0)
      expect(snapshot.historical_event_count).to eq(1)
      expect(snapshot.total_score).to eq(30)
    end

    it "uses a specified strategy version instead of the active one" do
      old_strategy = create(:scoring_strategy, version: 50, effective_at: 2.weeks.ago)
      point = create(:hazard_point, :registered_hazard, last_inspected_at: Time.current)

      snapshot = described_class.call(point, strategy_version: old_strategy.version).snapshot
      expect(snapshot.strategy_version).to eq(50)
    end
  end

  describe ".replay" do
    it "recomputes an old snapshot under a new strategy version without mutating it" do
      v1 = create(:scoring_strategy, version: 1, effective_at: 2.weeks.ago)
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      original = described_class.call(point, strategy_version: v1.version).snapshot

      v2_rules = ScoringRules::V1.rules.dup
      v2_items = v2_rules["items"].map { |i| i["key"] == "rainfall_24h" ? i.merge("max" => 80, "tiers" => [{ "min" => 0, "max" => nil, "score" => 80 }]) : i }
      v2_rules["items"] = v2_items
      v2 = create(:scoring_strategy, version: 2, effective_at: 1.day.ago, rules: v2_rules)

      replay_snapshot = described_class.replay(original, strategy_version: v2.version)

      expect(replay_snapshot.id).not_to eq(original.id)
      expect(replay_snapshot.strategy_version).to eq(2)
      expect(replay_snapshot.rainfall_24h_mm.to_f).to eq(original.rainfall_24h_mm.to_f)
      expect(replay_snapshot.total_score).to be > original.total_score

      expect(described_class.new(point).send(:replay_snapshot, original, v1).total_score).to eq(original.total_score)
    end
  end

  describe "concurrent calculation of the same evidence", :concurrency do
    self.use_transactional_tests = false

    it "produces consistent, deterministic scores from parallel calculations" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      threads = 4.times.map do
        Thread.new do
          Thread.current[:snapshot] = described_class.call(point, at: Time.current).snapshot
        end
      end
      snapshots = threads.map { |t| t.join[:snapshot] }

      expect(snapshots.all? { |s| s.total_score == 95 }).to be(true)
      expect(snapshots.map { |s| s.strategy_version }.uniq).to eq([strategy.version])
      expect(snapshots.map(&:id).uniq.length).to eq(4)
      expect(snapshots.all? { |s| s.score_breakdown.sum { |i| i["score"] } == 95 }).to be(true)
    end

    it "leaves exactly one snapshot when the same business_id is submitted concurrently" do
      point = create(:hazard_point, :cut_slope_building, last_inspected_at: nil)
      at = Time.current
      business_id = "evidence-concurrent-001"

      threads = 4.times.map do
        Thread.new do
          begin
            Thread.current[:outcome] = described_class.call(point, at: at, business_id: business_id)
          rescue described_class::PayloadConflict => e
            Thread.current[:error] = e
          end
        end
      end
      outcomes = threads.map { |t| t.join[:outcome] }.compact
      errors = threads.map { |t| t[:error] }.compact

      expect(errors).to be_empty
      expect(EvidenceSnapshot.where(business_id: business_id).count).to eq(1)
      expect(outcomes.map { |o| o.snapshot.id }.uniq.length).to eq(1)
      expect(outcomes.map(&:created)).to include(true)
      expect(outcomes.select { |o| o.created == false }.length).to eq(3)
    end
  end

  describe "business_id idempotency" do
    it "returns the existing snapshot when the same business_id and payload are reused" do
      point = create(:hazard_point, :registered_hazard, last_inspected_at: Time.current)
      at = Time.current

      first = described_class.call(point, at: at, business_id: "evidence-dedup-001", rainfall_24h_mm: 95)
      second = described_class.call(point, at: at, business_id: "evidence-dedup-001", rainfall_24h_mm: 95)

      expect(first.created).to be(true)
      expect(second.created).to be(false)
      expect(second.snapshot.id).to eq(first.snapshot.id)
      expect(EvidenceSnapshot.where(business_id: "evidence-dedup-001").count).to eq(1)
    end

    it "raises PayloadConflict when the same business_id has different evidence" do
      point = create(:hazard_point, :registered_hazard, last_inspected_at: Time.current)
      at = Time.current
      described_class.call(point, at: at, business_id: "evidence-conflict-001", rainfall_24h_mm: 95)

      expect {
        described_class.call(point, at: at, business_id: "evidence-conflict-001", rainfall_24h_mm: 180)
      }.to raise_error(described_class::PayloadConflict)
    end
  end
end
