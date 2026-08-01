require "rails_helper"
require "benchmark"

RSpec.describe QueueRetriever, :concurrency do
  self.use_transactional_tests = false

  def build_breakdown(total)
    remaining = total.to_i
    parts = [
      { "key" => "rainfall_24h", "name" => "24小时降水", "max" => 40 },
      { "key" => "historical_events", "name" => "历史事件次数", "max" => 25 },
      { "key" => "point_type_risk", "name" => "点位类型基础风险", "max" => 20 },
      { "key" => "inspection_recency", "name" => "巡查时效", "max" => 15 }
    ].map do |part|
      score = [remaining, part["max"]].min
      remaining -= score
      part.merge("score" => score, "reason" => "r")
    end
    expect(parts.sum { |p| p["score"] }).to eq(total.to_i)
    parts
  end

  describe "sorting 10,000+ points" do
    it "orders by total_score DESC with stable id ASC tiebreaker" do
      strategy = create(:scoring_strategy, effective_at: 1.week.ago)
      count = 10_000

      point_rows = count.times.map do |i|
        { name: "point-#{i}", point_type: "registered_hazard", road_accessible: true,
          historical_event_count: 0, latest_rainfall_24h_mm: 0,
          created_at: Time.current, updated_at: Time.current }
      end
      HazardPoint.insert_all(point_rows)
      point_ids = HazardPoint.order(:id).ids

      rng = Random.new(42)
      now = Time.current
      snapshot_rows = point_ids.map.with_index do |pid, idx|
        score = rng.rand(0..100)
        {
          hazard_point_id: pid,
          scoring_strategy_id: strategy.id,
          snapshot_at: now,
          rainfall_24h_mm: score,
          historical_event_count: 0,
          point_type: "registered_hazard",
          road_status: "accessible",
          last_inspected_at: nil,
          total_score: score,
          risk_level: "low",
          dispatch_status: "schedulable",
          score_breakdown: build_breakdown(score),
          explanation: { "summary" => "s" },
          created_at: now,
          updated_at: now
        }
      end
      snapshot_rows.each_slice(1000) { |slice| EvidenceSnapshot.insert_all(slice) }

      page = described_class.call(limit: 100)
      expect(page.total_count).to eq(count)

      elapsed = Benchmark.realtime do
        scores = []
        cursor = nil
        seen = Set.new
        loop do
          p = described_class.call(limit: 500, cursor: cursor)
          page_ids = p.items.map(&:id)
          expect(page_ids.uniq).to eq(page_ids)
          page_ids.each do |id|
            expect(seen.add?(id)).to be_truthy
          end
          scores.concat(p.items.map { |it| [it.total_score, it.id] })
          cursor = p.next_cursor
          break if cursor.nil?
        end
        expect(scores.length).to eq(count)
        expect(scores).to eq(scores.sort_by { |score, id| [-score, id] })
      end
      expect(elapsed).to be < 5.0
    end
  end

  describe "stable keyset pagination under continuous writes" do
    it "does not jump or duplicate rows when same-score rows are inserted mid-walk" do
      strategy = create(:scoring_strategy, effective_at: 1.week.ago)
      points = create_list(:hazard_point, 20, :registered_hazard, road_accessible: true,
                                                                 latest_rainfall_24h_mm: 50.0,
                                                                 historical_event_count: 1,
                                                                 last_inspected_at: nil)
      points.each { |p| PriorityCalculator.call(p, strategy: strategy) }

      scores = EvidenceSnapshot.pluck(:total_score).uniq
      expect(scores.length).to eq(1)

      page1 = described_class.call(limit: 10)
      expect(page1.items.length).to eq(10)
      seen_ids = page1.items.map(&:id)
      expect(seen_ids).to eq(seen_ids.sort)

      new_point = create(:hazard_point, :registered_hazard, latest_rainfall_24h_mm: 50.0,
                                                           historical_event_count: 1,
                                                           road_accessible: true,
                                                           last_inspected_at: nil)
      PriorityCalculator.call(new_point, strategy: strategy)

      page2 = described_class.call(limit: 10, cursor: page1.next_cursor)
      page2_ids = page2.items.map(&:id)

      expect(page2_ids & seen_ids).to be_empty
      expect(page2_ids).to eq(page2_ids.sort)
    end
  end

  describe "blocked filtering" do
    it "can exclude road-blocked points from the schedulable queue" do
      strategy = create(:scoring_strategy, effective_at: 1.week.ago)
      open_point = create(:hazard_point, :registered_hazard, road_accessible: true)
      blocked_point = create(:hazard_point, :road_slope_closed)

      [open_point, blocked_point].each do |p|
        PriorityCalculator.call(p, strategy: strategy)
      end

      all_page = described_class.call(limit: 10)
      expect(all_page.total_count).to eq(2)

      schedulable = described_class.call(limit: 10, include_blocked: false)
      expect(schedulable.total_count).to eq(1)
      expect(schedulable.items.first.dispatch_status).to eq("schedulable")

      blocked = described_class.call(limit: 10, dispatch_status: "blocked")
      expect(blocked.total_count).to eq(1)
      expect(blocked.items.first.dispatch_status).to eq("blocked")
      expect(blocked.items.first.risk_level).to eq("medium")
    end
  end
end
