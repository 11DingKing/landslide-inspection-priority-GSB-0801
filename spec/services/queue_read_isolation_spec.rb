require "rails_helper"

RSpec.describe "Queue read snapshot isolation", :concurrency do
  self.use_transactional_tests = false

  let(:v1_start) { Time.utc(2026, 1, 1, 0, 0, 0) }
  let(:boundary) { Time.utc(2026, 8, 2, 0, 0, 0) }
  let(:cutoff) { Time.utc(2026, 8, 2, 1, 0, 0) }
  let(:snap_time) { boundary }
  let!(:v1) do
    create(:scoring_strategy, version: 1, effective_at: v1_start,
           rules: ScoringRules::V1.rules)
  end
  let!(:v2) do
    create(:scoring_strategy, version: 2, effective_at: boundary,
           rules: ScoringRules::V2.rules)
  end

  it "freezes a traversal on the pinned strategy and cutoff, even when current scores move" do
    high = create(:hazard_point, name: "RDS-004", point_type: "cut_slope_building",
                                 road_accessible: true, latest_rainfall_24h_mm: 186.0,
                                 historical_event_count: 2, last_inspected_at: nil)
    rds002 = create(:hazard_point, name: "RDS-002", point_type: "road_slope",
                                   road_accessible: false, latest_rainfall_24h_mm: 112.0,
                                   historical_event_count: 0, last_inspected_at: nil)
    rds003 = create(:hazard_point, name: "RDS-003", point_type: "road_slope",
                                   road_accessible: false, latest_rainfall_24h_mm: 112.0,
                                   historical_event_count: 0, last_inspected_at: nil)

    old_snapshots = [high, rds002, rds003].map do |p|
      PriorityCalculator.call(p, at: snap_time).snapshot
    end
    high_old, rds002_old, rds003_old = old_snapshots

    expect(rds002_old.strategy_version).to eq(2)
    expect(rds002_old.total_score).to eq(52)
    expect(rds003_old.total_score).to eq(52)

    queue_read = QueueReadManager.create(business_id: "queue-20260802-01", at: cutoff)
    expect(queue_read.strategy_version).to eq(2)

    page1 = QueueRetriever.call(limit: 2, queue_read: queue_read)
    expect(page1.items.map(&:id)).to eq([high_old.id, rds002_old.id])
    expect(page1.total_count).to eq(3)
    original_cursor = page1.next_cursor
    expect(original_cursor).to be_present

    after_time = cutoff + 600
    rds002.update!(latest_rainfall_24h_mm: 210.0)
    rds002_new = PriorityCalculator.call(rds002, at: after_time,
                                              rainfall_24h_mm: 210.0).snapshot

    rds003_new = PriorityCalculator.call(rds003, at: after_time,
                                              rainfall_24h_mm: 112.0).snapshot

    expect(rds002_new.total_score).to eq(67)
    expect(rds002_new.id).not_to eq(rds002_old.id)
    expect(rds003_new.total_score).to eq(52)
    expect(rds003_new.id).not_to eq(rds003_old.id)

    page2 = QueueRetriever.call(limit: 2, cursor: original_cursor,
                                      queue_read: queue_read)
    expect(page2.items.size).to eq(1)
    expect(page2.items.first.id).to eq(rds003_old.id)
    expect(page2.items.map(&:id)).not_to include(rds002_new.id, rds003_new.id)
    expect(page2.next_cursor).to be_nil

    seen = [high_old.id, rds002_old.id, rds003_old.id]
    expect(seen.uniq).to eq(seen)
    expect(page1.total_count).to eq(3)
    expect(page2.total_count).to eq(3)

    new_read = QueueReadManager.create(business_id: "queue-20260802-02",
                                      at: after_time + 60)
    new_page = QueueRetriever.call(limit: 10, queue_read: new_read)
    new_ids = new_page.items.map(&:id)
    expect(new_ids).to eq([high_old.id, rds002_new.id, rds003_new.id])
    expect(new_ids).to include(rds002_new.id, rds003_new.id)
    expect(new_ids).not_to include(rds002_old.id, rds003_old.id)
  end

  it "keeps blocked dispatch status on the frozen snapshots without zeroing risk" do
    point = create(:hazard_point, name: "RDS-002", point_type: "road_slope",
                                  road_accessible: false, latest_rainfall_24h_mm: 210.0,
                                  historical_event_count: 0, last_inspected_at: nil)
    snap = PriorityCalculator.call(point, at: snap_time).snapshot

    queue_read = QueueReadManager.create(business_id: "queue-blocked-01", at: cutoff)
    page = QueueRetriever.call(limit: 10, queue_read: queue_read)

    item = page.items.find { |i| i.id == snap.id }
    expect(item.dispatch_status).to eq("blocked")
    expect(item.total_score).to eq(67)
    expect(item.risk_level).to eq("high")
  end

  it "is idempotent for the same queue_read business_id" do
    first = QueueReadManager.create(business_id: "queue-idem-01", at: cutoff)
    second = QueueReadManager.create(business_id: "queue-idem-01", at: cutoff + 1000)
    expect(second.id).to eq(first.id)
    expect(second.cutoff_at).to eq(first.cutoff_at)
  end

  it "still allows old v1/v2 snapshots to be replayed after the new traversal" do
    point = create(:hazard_point, name: "RDS-002", point_type: "road_slope",
                                  road_accessible: false, latest_rainfall_24h_mm: 112.0,
                                  historical_event_count: 0, last_inspected_at: nil)
    old_v2 = PriorityCalculator.call(point, at: boundary).snapshot
    expect(old_v2.strategy_version).to eq(2)

    replayed = PriorityCalculator.replay(old_v2, strategy_version: 1)
    expect(replayed.strategy_version).to eq(1)
    expect(replayed.rainfall_24h_mm.to_f).to eq(old_v2.rainfall_24h_mm.to_f)

    expect(old_v2.reload.strategy_version).to eq(2)
    expect(old_v2.total_score).to eq(52)
  end
end
