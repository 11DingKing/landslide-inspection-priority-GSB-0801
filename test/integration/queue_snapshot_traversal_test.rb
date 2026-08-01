# frozen_string_literal: true

require "test_helper"

# The user scenario: capture queue snapshot `queue-20260802-01`, turn the
# first page, then write new evidence for RDS-002 and a tie-score point and
# recompute (moving the live current pointers). Continuing with the original
# cursor against the snapshot must traverse exactly the pinned membership —
# no skips, no duplicates — while a fresh traversal sees the updates.
class QueueSnapshotTraversalTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  BOUNDARY = "2026-08-02T00:00:00Z"
  SNAP_NAME = "queue-20260802-01"

  setup do
    rules_v2 = RULES_V1.deep_merge("rainfall_24h" => {
      "thresholds" => [
        { "gte_mm" => 200, "score" => 40 }, { "gte_mm" => 150, "score" => 38 },
        { "gte_mm" => 100, "score" => 30 }, { "gte_mm" => 50, "score" => 20 },
        { "gte_mm" => 25, "score" => 10 }
      ]
    })
    build_strategy(version: 1, from: Time.zone.parse("2026-01-01"),
                   to: Time.zone.parse(BOUNDARY), status: "published")
    build_strategy(version: 2, rules: rules_v2, from: Time.zone.parse(BOUNDARY),
                   status: "published")

    # RDS-002: current at capture = the boundary snapshot (65, v2, blocked).
    @rds = build_point("RDS-002")
    @rds_old_snapshot = build_snapshot(
      @rds, client_reference: "evidence-rds-002-old",
      rainfall_24h_mm: 112, last_inspected_at: Time.zone.parse("2026-05-03T08:00:00Z"),
      road_accessible: false, captured_at: Time.zone.parse("2026-08-01T08:00:00Z")
    )
    @rds_boundary_snapshot = build_snapshot(
      @rds, client_reference: "evidence-rds-002-20260802-0000",
      rainfall_24h_mm: 210, last_inspected_at: Time.zone.parse("2026-05-04T00:00:00Z"),
      road_accessible: false, captured_at: Time.zone.parse(BOUNDARY)
    )
    # Two tie points at 55, plus two filler points -> 5 current entries.
    @tie_a = make_scored_point("TIE-A", rainfall: 112, inspected: "2026-05-03T08:00:00Z")
    @tie_b = make_scored_point("TIE-B", rainfall: 112, inspected: "2026-05-03T08:00:00Z")
    @low_1 = make_scored_point("LOW-1", rainfall: 60, inspected: "2026-08-01T08:00:00Z")
    @low_2 = make_scored_point("LOW-2", rainfall: 10, inspected: nil)

    PriorityCalculator.call(snapshot: @rds_old_snapshot)      # 55 v1 (superseded)
    @rds_current_at_capture = PriorityCalculator.call(snapshot: @rds_boundary_snapshot) # 65 v2
  end

  teardown do
    clean_tables!
  end

  test "cursor traversal pinned to the queue snapshot survives current movement" do
    post "/api/v1/queue_snapshots",
         params: { queue_snapshot: { name: SNAP_NAME, at: BOUNDARY } }, as: :json
    assert_response :created
    meta = response.parsed_body
    assert_equal 2, meta["strategy_version"] # fixed on strategy round 2
    assert_equal 5, meta["entry_count"]
    pinned_ids = QueueSnapshot.find_by!(name: SNAP_NAME).score_records.order(total_score: :desc, id: :asc).pluck(:id)
    assert_includes pinned_ids, @rds_current_at_capture.id

    # --- page 1 on the snapshot ---
    get "/api/v1/inspection_queue", params: { snapshot: SNAP_NAME, limit: 2 }
    assert_response :ok
    page1 = response.parsed_body
    assert_equal SNAP_NAME, page1["snapshot"]["name"]
    assert_equal 2, page1["snapshot"]["strategy_version"]
    assert_equal [65, 55], page1["entries"].map { |e| e["total_score"] }
    assert_equal @rds_current_at_capture.id, page1["entries"].first["score_record_id"]
    cursor = page1["next_cursor"]
    assert cursor.present?

    # --- writes: new evidence + recompute for RDS-002 and tie point TIE-A ---
    rds_new_snapshot = build_snapshot(
      @rds, client_reference: "evidence-rds-002-later",
      rainfall_24h_mm: 120, last_inspected_at: Time.zone.parse("2026-05-04T00:00:00Z"),
      road_accessible: false, captured_at: Time.zone.parse("2026-08-02T01:00:00Z")
    )
    rds_new_record = PriorityCalculator.call(snapshot: rds_new_snapshot) # 55, v2
    tie_a_new_snapshot = build_snapshot(
      @tie_a[:point], client_reference: "evidence-tie-a-later",
      rainfall_24h_mm: 210, last_inspected_at: @tie_a[:snapshot].last_inspected_at,
      road_accessible: true, captured_at: Time.zone.parse("2026-08-02T01:00:00Z")
    )
    tie_a_new_record = PriorityCalculator.call(snapshot: tie_a_new_snapshot) # 65, v2
    assert_not_equal @rds_current_at_capture.id, rds_new_record.id

    # --- continue with the ORIGINAL cursor on the snapshot ---
    traversed = page1["entries"].map { |e| e["score_record_id"] }
    loop do
      get "/api/v1/inspection_queue", params: { snapshot: SNAP_NAME, limit: 2, cursor: cursor }
      assert_response :ok
      body = response.parsed_body
      traversed.concat(body["entries"].map { |e| e["score_record_id"] })
      cursor = body["next_cursor"]
      break if cursor.nil?
    end

    # Exactly the pinned membership: nothing skipped, nothing duplicated,
    # and still the OLD score records of the moved points.
    assert_equal pinned_ids.sort, traversed.sort
    assert_equal traversed.uniq.size, traversed.size
    assert_includes traversed, @rds_current_at_capture.id
    assert_not_includes traversed, rds_new_record.id
    assert_not_includes traversed, tie_a_new_record.id

    # --- a fresh (live) traversal sees the updated results ---
    get "/api/v1/inspection_queue", params: { limit: 10 }
    live_ids = response.parsed_body["entries"].map { |e| e["score_record_id"] }
    assert_includes live_ids, rds_new_record.id
    assert_includes live_ids, tie_a_new_record.id
    assert_not_includes live_ids, @rds_current_at_capture.id

    # --- old score explanations remain replayable across the v1/v2 boundary ---
    get "/api/v1/priorities/#{@rds_current_at_capture.id}/explanation"
    assert_response :ok
    assert_equal 2, response.parsed_body["strategy_version"]
    assert_equal 65, response.parsed_body["total_score"]
    assert_equal "blocked", response.parsed_body["scheduling_status"]

    post "/api/v1/priorities", params: { priority: { evidence_snapshot_id: @rds_old_snapshot.id } }, as: :json
    assert_response :created
    assert_equal 1, response.parsed_body["strategy_version"] # pre-boundary evidence -> v1
    assert_equal 55, response.parsed_body["total_score"]
  end

  test "re-capturing the same name is idempotent" do
    post "/api/v1/queue_snapshots", params: { queue_snapshot: { name: SNAP_NAME } }, as: :json
    assert_response :created
    first_id = response.parsed_body["id"]

    post "/api/v1/queue_snapshots", params: { queue_snapshot: { name: SNAP_NAME } }, as: :json

    assert_response :ok
    assert_equal first_id, response.parsed_body["id"]
    assert_equal 1, QueueSnapshot.where(name: SNAP_NAME).count
  end

  private

  def make_scored_point(code, rainfall:, inspected:)
    point = build_point(code)
    snapshot = build_snapshot(
      point, client_reference: "evidence-#{code.downcase}-seed",
      rainfall_24h_mm: rainfall,
      last_inspected_at: inspected && Time.zone.parse(inspected),
      road_accessible: true, captured_at: Time.zone.parse("2026-08-01T08:00:00Z")
    )
    record = PriorityCalculator.call(snapshot: snapshot)
    { point: point, snapshot: snapshot, record: record }
  end
end
