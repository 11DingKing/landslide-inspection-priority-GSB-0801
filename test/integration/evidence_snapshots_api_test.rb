# frozen_string_literal: true

require "test_helper"

class EvidenceSnapshotsApiTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  BOUNDARY = "2026-08-02T00:00:00Z"

  setup do
    @v1 = build_strategy(version: 1, from: Time.zone.parse("2026-01-01"),
                         to: Time.zone.parse(BOUNDARY), status: "published")
    rules_v2 = RULES_V1.deep_merge("rainfall_24h" => {
      "thresholds" => [
        { "gte_mm" => 200, "score" => 40 }, { "gte_mm" => 150, "score" => 38 },
        { "gte_mm" => 100, "score" => 30 }, { "gte_mm" => 50, "score" => 20 },
        { "gte_mm" => 25, "score" => 10 }
      ]
    })
    @v2 = build_strategy(version: 2, rules: rules_v2,
                         from: Time.zone.parse(BOUNDARY), status: "published")
    @point = build_point("RDS-002")
  end

  teardown do
    clean_tables!
  end

  def boundary_payload(reference: "evidence-rds-002-20260802-0000", rainfall: 210)
    {
      evidence_snapshot: {
        client_reference: reference,
        rainfall_24h_mm: rainfall,
        historical_event_count: 0,
        last_inspected_at: "2026-05-04T00:00:00Z",
        road_accessible: false,
        captured_at: BOUNDARY
      }
    }
  end

  test "snapshot captured exactly at the boundary binds v2; blocked keeps risk" do
    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots",
         params: boundary_payload, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal "evidence-rds-002-20260802-0000", body["client_reference"]
    score = body["score"]
    assert_equal 2, score["strategy_version"]
    assert_equal 65, score["total_score"] # 40 + 0 + 25, inaccessibility did NOT lower it
    assert_equal "medium", score["risk_level"]
    assert_equal "blocked", score["scheduling_status"]
    assert_equal score["components_sum"], score["total_score"]
  end

  test "snapshot captured just before the boundary binds v1" do
    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots", params: {
      evidence_snapshot: {
        client_reference: "evidence-rds-002-before-boundary",
        rainfall_24h_mm: 112, historical_event_count: 0,
        last_inspected_at: "2026-05-03T08:00:00Z",
        road_accessible: false, captured_at: "2026-08-01T08:00:00Z"
      }
    }, as: :json

    assert_response :created
    score = response.parsed_body["score"]
    assert_equal 1, score["strategy_version"]
    assert_equal 55, score["total_score"]
    assert_equal "blocked", score["scheduling_status"]
  end

  test "resubmitting identical content returns the original snapshot and score" do
    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots",
         params: boundary_payload, as: :json
    assert_response :created
    first = response.parsed_body

    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots",
         params: boundary_payload, as: :json

    assert_response :ok
    second = response.parsed_body
    assert_equal first["id"], second["id"]
    assert_equal first["score"]["score_record_id"], second["score"]["score_record_id"]
    assert_equal 1, EvidenceSnapshot.where(client_reference: "evidence-rds-002-20260802-0000").count
    assert_equal 1, ScoreRecord.count
  end

  test "same identifier with different content conflicts" do
    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots",
         params: boundary_payload, as: :json
    assert_response :created

    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots",
         params: boundary_payload(rainfall: 186), as: :json

    assert_response :conflict
    assert_match(/different content/, response.parsed_body["error"])
    assert_equal 210, EvidenceSnapshot.find_by(client_reference: "evidence-rds-002-20260802-0000").rainfall_24h_mm
  end

  test "identifier pointing at another hazard point conflicts" do
    post "/api/v1/hazard_points/#{@point.id}/evidence_snapshots",
         params: boundary_payload, as: :json
    other = build_point("OTHER-1")

    post "/api/v1/hazard_points/#{other.id}/evidence_snapshots",
         params: boundary_payload, as: :json

    assert_response :conflict
  end

  test "concurrent identical submissions leave exactly one snapshot and one score" do
    results = Concurrent::Array.new
    bodies = Concurrent::Array.new
    url = "/api/v1/hazard_points/#{@point.id}/evidence_snapshots"
    threads = 3.times.map do
      Thread.new do
        session = open_session
        session.post url, params: boundary_payload, as: :json
        results << session.response.status
        bodies << session.response.parsed_body
      end
    end
    threads.each(&:join)

    assert_equal 1, EvidenceSnapshot.where(client_reference: "evidence-rds-002-20260802-0000").count
    assert_equal 1, ScoreRecord.count
    assert results.all? { |s| [200, 201].include?(s) },
           "unexpected statuses: #{results.inspect} bodies: #{bodies.inspect}"
  end

  test "concurrent computation during the strategy switch keeps one current score and never rewrites history" do
    old_snapshot = @point.evidence_snapshots.create!(
      client_reference: "evidence-rds-002-old", rainfall_24h_mm: 112,
      historical_event_count: 0, last_inspected_at: Time.zone.parse("2026-05-03T08:00:00Z"),
      road_accessible: false, captured_at: Time.zone.parse("2026-08-01T08:00:00Z")
    )
    old_record = PriorityCalculator.call(snapshot: old_snapshot)
    boundary_snapshot = @point.evidence_snapshots.create!(
      client_reference: "evidence-rds-002-20260802-0000", rainfall_24h_mm: 210,
      historical_event_count: 0, last_inspected_at: Time.zone.parse("2026-05-04T00:00:00Z"),
      road_accessible: false, captured_at: Time.zone.parse(BOUNDARY)
    )

    threads = 4.times.map do
      Thread.new { PriorityCalculator.call(snapshot: boundary_snapshot) }
    end
    results = threads.map(&:value)

    # exactly one new record, computed under v2, and it is the only current one
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, ScoreRecord.current.where(hazard_point: @point).count
    assert_equal @v2.id, ScoreRecord.current.find_by(hazard_point: @point).strategy_version_id

    # the historical record is untouched: same strategy, same scores
    old_record.reload
    assert_not old_record.is_current
    assert_equal @v1.id, old_record.strategy_version_id
    assert_equal 55, old_record.total_score
    assert_equal({ "rainfall_24h" => 30, "historical_events" => 0, "inspection_recency" => 25 },
                 old_record.components)
  end
end
