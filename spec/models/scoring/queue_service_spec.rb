require "rails_helper"

RSpec.describe Scoring::QueueService do
  let(:strategy) { create(:scoring_strategy) }

  before { strategy }

  def make_point_with_score(kind:, rainfall:, history:, last_inspected:,
                            blocked: false)
    point = create(:hazard_point, kind: kind,
                                  road_accessible: !blocked)
    snap = create(:evidence_snapshot,
                  hazard_point: point,
                  snapshot_time: Time.current,
                  rainfall_24h_mm: rainfall,
                  historical_event_count: history,
                  last_inspected_at: last_inspected,
                  road_accessible: !blocked)
    Scoring::PriorityComputer.call(snap, now: Time.current)
    point
  end

  it "orders by total_score DESC, then hazard_point_id ASC" do
    p_low = make_point_with_score(kind: "registered_hazard", rainfall: 10,
                                  history: 0, last_inspected: 1.hour.ago)
    p_med = make_point_with_score(kind: "road_slope", rainfall: 112,
                                  history: 0, last_inspected: 70.hours.ago)
    p_hi  = make_point_with_score(kind: "cut_slope_building", rainfall: 186,
                                  history: 2, last_inspected: nil)

    result = described_class.list(per_page: 50)
    ids = result[:items].map(&:hazard_point_id)
    expect(ids).to eq([p_hi.id, p_med.id, p_low.id])
  end

  it "includes blocked points but marks them blocked without lowering score" do
    blocked = make_point_with_score(kind: "road_slope", rainfall: 112,
                                    history: 0, last_inspected: 70.hours.ago,
                                    blocked: true)
    result = described_class.list(per_page: 50)
    row = result[:items].find { |i| i.hazard_point_id == blocked.id }
    expect(row.dispatch_status).to eq("blocked")
    expect(row.total_score).to eq(50)
    expect(row.risk_level).to eq("medium")
  end

  it "can filter out blocked points with include_blocked=false" do
    blocked = make_point_with_score(kind: "road_slope", rainfall: 112,
                                    history: 0, last_inspected: 70.hours.ago,
                                    blocked: true)
    open_p  = make_point_with_score(kind: "registered_hazard", rainfall: 95,
                                    history: 1, last_inspected: 6.hours.ago)
    result = described_class.list(include_blocked: false, per_page: 50)
    ids = result[:items].map(&:hazard_point_id)
    expect(ids).to include(open_p.id)
    expect(ids).not_to include(blocked.id)
  end

  it "paginates with offset/limit without shuffling equal-score pages" do
    # Create 10 points that all produce the SAME total_score (34: rain 95
    # bucket 18 + 1 history 8 + within_24h 0 + registered 8).
    points = 10.times.map do
      make_point_with_score(kind: "registered_hazard", rainfall: 95,
                            history: 1, last_inspected: 6.hours.ago)
    end
    sorted_ids = points.sort_by(&:id).map(&:id)

    page1 = described_class.list(per_page: 4)
    page2 = described_class.list(per_page: 4, offset: 4)
    page3 = described_class.list(per_page: 4, offset: 8)

    actual = page1[:items].map(&:hazard_point_id) +
             page2[:items].map(&:hazard_point_id) +
             page3[:items].map(&:hazard_point_id)
    expect(actual).to eq(sorted_ids)
    expect(page1[:total]).to eq(10)
  end

  it "paginates with a cursor and never repeats or skips items" do
    15.times.map do
      make_point_with_score(kind: "registered_hazard", rainfall: 95,
                            history: 1, last_inspected: 6.hours.ago)
    end
    expected_order = PriorityScore.order(total_score: :desc, hazard_point_id: :asc)
                                  .pluck(:hazard_point_id)

    collected = []
    cursor = nil
    loop do
      page = described_class.list(per_page: 4, cursor: cursor)
      collected.concat(page[:items].map(&:hazard_point_id))
      break unless page[:has_more]

      cursor = page[:next_cursor]
    end
    expect(collected).to eq(expected_order)
  end

  it "stably sorts at least 10,000 points and keeps page order under inserts",
     :slow do
    count = 10_000
    points = Array.new(count) do |i|
      point = create(:hazard_point,
                     kind: %w[cut_slope_building road_slope registered_hazard][i % 3],
                     road_accessible: true)
      rain = [10, 50, 95, 112, 150, 200][i % 6]
      snap = create(:evidence_snapshot,
                    hazard_point: point,
                    snapshot_time: Time.current,
                    rainfall_24h_mm: rain,
                    historical_event_count: i % 4,
                    last_inspected_at: (i.even? ? 6.hours.ago : nil))
      Scoring::PriorityComputer.call(snap, now: Time.current)
      point
    end

    page_a = described_class.list(per_page: 100)[:items].map(&:hazard_point_id)

    # Insert 500 new points concurrently while reading another page.
    500.times do |i|
      p = create(:hazard_point, kind: "registered_hazard")
      s = create(:evidence_snapshot, hazard_point: p, rainfall_24h_mm: 95,
                                     historical_event_count: 1,
                                     last_inspected_at: 6.hours.ago,
                                     snapshot_time: Time.current)
      Scoring::PriorityComputer.call(s, now: Time.current)
    end

    page_b = described_class.list(per_page: 100)[:items].map(&:hazard_point_id)

    # Existing rows on the first page must be identical (same score ties are
    # broken by id ASC, and new inserts always get larger ids, so they can
    # only appear at the END of equal-score groups).
    expect(page_b.first(100)).to eq(page_a)
    total = described_class.list(per_page: 1)[:total]
    expect(total).to be >= 10_000
  end
end
