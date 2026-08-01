# frozen_string_literal: true

require "test_helper"

# Queue stability: 10_000+ points, many with identical scores, paginated with
# keyset cursors while new records are being written mid-iteration. Pages
# must be complete, duplicate-free and in (total_score DESC, id ASC) order.
class InspectionQueueTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  POINT_COUNT = 10_000
  PAGE_SIZE = 500

  setup do
    @strategy = build_strategy(version: 1, status: "published")
    now = Time.current

    points = POINT_COUNT.times.map do |i|
      { external_code: format("BULK-%05d", i), name: "bulk #{i}", kind: "registered_hazard",
        created_at: now, updated_at: now }
    end
    HazardPoint.insert_all(points)
    point_ids = HazardPoint.order(:id).pluck(:id)

    snapshots = point_ids.map do |pid|
      { hazard_point_id: pid, rainfall_24h_mm: 0, historical_event_count: 0,
        road_accessible: true, captured_at: now, created_at: now, updated_at: now }
    end
    EvidenceSnapshot.insert_all(snapshots)
    snapshot_ids = EvidenceSnapshot.order(:id).pluck(:id)

    records = point_ids.each_with_index.map do |pid, i|
      # Only three distinct totals -> massive ties to stress the tie-breaker.
      total = [55, 35, 10][i % 3]
      { hazard_point_id: pid, evidence_snapshot_id: snapshot_ids[i],
        strategy_version_id: @strategy.id,
        components: { "rainfall_24h" => 0, "historical_events" => 0,
                      "inspection_recency" => total },
        total_score: total, risk_level: "low", scheduling_status: "schedulable",
        is_current: true, computed_at: now, created_at: now, updated_at: now }
    end
    records.each_slice(1000) { |slice| ScoreRecord.insert_all(slice) }
  end

  teardown do
    clean_tables!
  end

  test "paginates 10k records with stable order and no duplicates" do
    seen_ids = []
    seen_pairs = []
    cursor = nil
    pages = 0

    loop do
      entry = InspectionQueue.call(limit: PAGE_SIZE, cursor: cursor)
      seen_ids.concat(entry.records.map(&:id))
      seen_pairs.concat(entry.records.map { |r| [r.total_score, r.id] })
      pages += 1

      # Simulate continuous writes mid-iteration: new current records with a
      # HIGHER score than any cursor position. They sort "before" the cursor,
      # so keyset pagination must keep the pages already turned untouched:
      # no duplicates, no order jumps.
      if pages == 2
        inject_new_record(total_score: 100)
        inject_new_record(total_score: 90)
      end

      break if entry.next_cursor.nil?
      cursor = entry.next_cursor
    end

    assert_equal POINT_COUNT, seen_ids.size
    assert_equal seen_ids.uniq.size, seen_ids.size, "duplicate entries across pages"
    expected = seen_pairs.sort_by { |score, id| [-score, id] }
    assert_equal expected, seen_pairs, "order must be (total_score DESC, id ASC)"
    assert_operator pages, :>=, POINT_COUNT / PAGE_SIZE
  end

  test "a record inserted with a tying score appears exactly once, in order" do
    ScoreRecord.delete_all
    50.times { |i| inject_new_record(total_score: 35) }

    seen_ids = []
    cursor = nil
    loop do
      entry = InspectionQueue.call(limit: 10, cursor: cursor)
      seen_ids.concat(entry.records.map(&:id))
      inject_new_record(total_score: 35) if seen_ids.size == 20 # tie written mid-scan
      break if entry.next_cursor.nil?
      cursor = entry.next_cursor
    end

    assert_equal 51, seen_ids.size
    assert_equal seen_ids.uniq.sort, seen_ids.sort, "no duplicates; ids must ascend within the tie"
  end

  test "scheduling_status filter keeps blocked risk levels intact" do
    point = build_point("Q-BLOCKED")
    snapshot = build_snapshot(point, rainfall_24h_mm: 112, road_accessible: false,
                              last_inspected_at: 90.days.ago, captured_at: 1.hour.ago)
    record = PriorityCalculator.call(snapshot: snapshot)

    blocked = InspectionQueue.call(limit: 10, cursor: nil, scheduling_status: "blocked")

    assert_equal "medium", record.risk_level
    assert_equal "blocked", record.scheduling_status
    assert_includes blocked.records.map(&:id), record.id
    assert_not ScoreRecord.current.where(hazard_point: point, scheduling_status: "schedulable").exists?
  end

  test "invalid cursor is rejected" do
    assert_raises(ActionController::BadRequest) do
      InspectionQueue.call(limit: 10, cursor: "not-a-cursor")
    end
  end

  private

  def inject_new_record(total_score:)
    point = build_point("Q-INJECT-#{SecureRandom.hex(4)}")
    snapshot = build_snapshot(point, captured_at: 1.hour.ago)
    ScoreRecord.create!(hazard_point: point, evidence_snapshot: snapshot,
                        strategy_version: @strategy,
                        components: { "rainfall_24h" => 0, "historical_events" => 0,
                                      "inspection_recency" => total_score },
                        total_score: total_score, risk_level: "low",
                        scheduling_status: "schedulable", is_current: true,
                        computed_at: Time.current)
  end
end
