# frozen_string_literal: true

require "test_helper"

class PrioritiesApiTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  teardown do
    clean_tables!
  end

  test "priority response includes component scores, ranges, rule version and snapshot time" do
    build_strategy(version: 1, status: "published")
    point = build_point("API-1")
    captured = Time.zone.parse("2026-08-01 06:00:00")
    snapshot = build_snapshot(point, rainfall_24h_mm: 186, historical_event_count: 2,
                              last_inspected_at: nil, captured_at: captured)

    post "/api/v1/priorities", params: { priority: { evidence_snapshot_id: snapshot.id } }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal 100, body["total_score"]
    assert_equal 1, body["strategy_version"]
    assert_equal captured.iso8601, body["snapshot_captured_at"]
    assert_equal %w[historical_events inspection_recency rainfall_24h],
                 body["components"].map { |c| c["name"] }.sort
    body["components"].each do |component|
      assert component["score"].between?(component["range"]["min"], component["range"]["max"])
    end
    assert_equal body["components"].sum { |c| c["score"] }, body["total_score"]
  end

  test "explanation endpoint returns the same locked breakdown" do
    build_strategy(version: 1, status: "published")
    snapshot = build_snapshot(build_point("API-2"), rainfall_24h_mm: 112,
                              road_accessible: false, last_inspected_at: 90.days.ago,
                              captured_at: 1.hour.ago)
    record = PriorityCalculator.call(snapshot: snapshot)

    get "/api/v1/priorities/#{record.id}/explanation"

    assert_response :ok
    body = response.parsed_body
    assert_equal "medium", body["risk_level"]
    assert_equal "blocked", body["scheduling_status"]
    assert_equal body["components_sum"], body["total_score"]
    assert_equal 1, body["strategy_version"]
  end

  test "replaying a historical snapshot returns the identical record" do
    boundary = Time.current + 1.day
    build_strategy(version: 1, to: boundary, status: "published")
    snapshot = build_snapshot(build_point("API-3"), rainfall_24h_mm: 186,
                              historical_event_count: 2,
                              captured_at: Time.zone.parse("2026-08-01 03:00:00"))

    post "/api/v1/priorities", params: { priority: { evidence_snapshot_id: snapshot.id } }, as: :json
    first = response.parsed_body

    # a later strategy for future evidence must not rewrite history
    build_strategy(version: 2, from: boundary, status: "published")

    post "/api/v1/priorities", params: { priority: { evidence_snapshot_id: snapshot.id } }, as: :json
    second = response.parsed_body

    assert_equal first["score_record_id"], second["score_record_id"]
    assert_equal first["total_score"], second["total_score"]
    assert_equal 1, second["strategy_version"]
  end

  test "comparative replay under an explicit strategy version" do
    boundary = Time.current + 1.day
    build_strategy(version: 1, to: boundary, status: "published")
    v2 = build_strategy(version: 2, from: boundary, status: "published")
    snapshot = build_snapshot(build_point("API-4"), rainfall_24h_mm: 95, historical_event_count: 1,
                              captured_at: 1.hour.ago)

    post "/api/v1/priorities", params: {
      priority: { evidence_snapshot_id: snapshot.id, strategy_version_id: v2.id }
    }, as: :json

    assert_response :created
    assert_equal 2, response.parsed_body["strategy_version"]
  end

  test "computing a snapshot with no applicable strategy returns 422" do
    build_strategy(version: 1, from: Time.current + 1.day, status: "published")
    snapshot = build_snapshot(build_point("API-5"), captured_at: 1.hour.ago)

    post "/api/v1/priorities", params: { priority: { evidence_snapshot_id: snapshot.id } }, as: :json

    assert_response :unprocessable_entity
    assert_match(/no published strategy/, response.parsed_body["error"])
  end
end
