# frozen_string_literal: true

require "test_helper"

class InspectionQueueApiTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  teardown do
    clean_tables!
  end

  test "queue returns current scores ordered by priority with cursor pagination" do
    build_strategy(version: 1, status: "published")
    high = build_snapshot(build_point("Q-API-1"), rainfall_24h_mm: 186,
                          historical_event_count: 2, captured_at: 1.hour.ago)
    blocked = build_snapshot(build_point("Q-API-2"), rainfall_24h_mm: 112,
                             road_accessible: false, last_inspected_at: 95.days.ago,
                             captured_at: 1.hour.ago)
    low = build_snapshot(build_point("Q-API-3"), rainfall_24h_mm: 95,
                         historical_event_count: 1, last_inspected_at: Time.current,
                         captured_at: 1.hour.ago)
    [high, blocked, low].each { |s| PriorityCalculator.call(snapshot: s) }

    get "/api/v1/inspection_queue", params: { limit: 2 }

    assert_response :ok
    body = response.parsed_body
    assert_equal 2, body["entries"].size
    assert_equal [100, 55], body["entries"].map { |e| e["total_score"] }
    assert_equal "blocked", body["entries"].last["scheduling_status"]
    assert_equal "medium", body["entries"].last["risk_level"]
    assert body["next_cursor"].present?

    get "/api/v1/inspection_queue", params: { limit: 2, cursor: body["next_cursor"] }

    assert_response :ok
    rest = response.parsed_body
    assert_equal [35], rest["entries"].map { |e| e["total_score"] }
    assert_nil rest["next_cursor"]
  end

  test "queue entries always carry rule version and snapshot time" do
    build_strategy(version: 1, status: "published")
    captured = Time.zone.parse("2026-08-01 06:30:00")
    snapshot = build_snapshot(build_point("Q-API-4"), rainfall_24h_mm: 60, captured_at: captured)
    PriorityCalculator.call(snapshot: snapshot)

    get "/api/v1/inspection_queue"

    entry = response.parsed_body["entries"].first
    assert_equal 1, entry["strategy_version"]
    assert_equal captured.iso8601, entry["snapshot_captured_at"]
    assert_equal entry["components"].values.sum, entry["total_score"]
  end

  test "invalid cursor returns 400" do
    get "/api/v1/inspection_queue", params: { cursor: "@@@" }
    assert_response :bad_request
  end
end
