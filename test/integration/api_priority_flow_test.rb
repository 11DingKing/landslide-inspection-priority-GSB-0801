require "test_helper"

class Api::V1::PriorityFlowTest < ActionDispatch::IntegrationTest
  setup do
    @policy = create_policy!(version: "api-v1", effective_from: Time.utc(2026, 7, 1))
  end

  test "full flow: create point, snapshot, compute, explain, queue" do
    post "/api/v1/hazard_points",
         params: { hazard_point: { code: "API-1", name: "切坡建房点", category: "cut_slope_housing" } },
         as: :json
    assert_response :created
    point_id = response.parsed_body["id"]

    post "/api/v1/hazard_points/#{point_id}/evidence_snapshots",
         params: { evidence_snapshot: { captured_at: "2026-07-10T00:00:00Z", rainfall_mm_24h: 186,
                                        historical_event_count: 2, road_accessible: true } },
         as: :json
    assert_response :created
    snap_id = response.parsed_body["id"]
    assert response.parsed_body["content_digest"].present?

    post "/api/v1/evidence_snapshots/#{snap_id}/priority", as: :json
    assert_response :created
    body = response.parsed_body
    # Explanation returns per-component scores AND the policy version.
    assert_equal "api-v1", body.dig("scoring_policy", "version")
    assert_equal 4, body["components"].size
    assert_equal body["total_score"], body["components_sum"]
    assert_equal body["total_score"], body["components"].sum { |c| c["score"] }

    get "/api/v1/scoring_policies/#{@policy.id}/queue", as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["items"].size
  end

  test "road closed keeps risk level and marks scheduling blocked over the API" do
    point = create_point!(code: "API-BLOCK", category: "road_slope")
    post "/api/v1/hazard_points/#{point.id}/evidence_snapshots",
         params: { evidence_snapshot: { captured_at: "2026-07-10T00:00:00Z", rainfall_mm_24h: 112,
                                        historical_event_count: 0, road_accessible: false,
                                        point_last_inspected_at: "2025-05-01T00:00:00Z" } },
         as: :json
    snap_id = response.parsed_body["id"]

    post "/api/v1/evidence_snapshots/#{snap_id}/priority", as: :json
    body = response.parsed_body
    assert_equal "blocked", body["scheduling_status"]
    assert_operator body["total_score"], :>, 0
    assert_equal "moderate", body["risk_level"]
  end

  test "publishing an overlapping policy returns 409" do
    # @policy is open-ended from 2026-07-01, so any overlapping window is rejected.
    post "/api/v1/scoring_policies",
         params: { scoring_policy: { version: "api-dup", effective_from: "2026-08-01T00:00:00Z",
                                     definition: build_baseline_definition } },
         as: :json
    assert_response :created
    dup_id = response.parsed_body["id"]

    post "/api/v1/scoring_policies/#{dup_id}/publish", as: :json
    assert_response :conflict
    assert_equal "overlapping_policy", response.parsed_body["error"]
  end

  test "bound v1, publish v2 from boundary: old snapshot binds v1, new binds v2, current follows latest" do
    # @policy (api-v1) is open-ended from 2026-07-01. Bound it at the boundary,
    # then publish v2 from the boundary onward.
    patch "/api/v1/scoring_policies/#{@policy.id}/bound",
          params: { scoring_policy: { effective_until: "2026-08-02T00:00:00Z" } }, as: :json
    assert_response :success
    assert_equal "2026-08-02T00:00:00Z", response.parsed_body["effective_until"]

    post "/api/v1/scoring_policies",
         params: { scoring_policy: { version: "api-v2", effective_from: "2026-08-02T00:00:00Z",
                                     definition: build_baseline_definition } }, as: :json
    v2_id = response.parsed_body["id"]
    post "/api/v1/scoring_policies/#{v2_id}/publish", as: :json
    assert_response :success

    point = create_point!(code: "RDS-INT", category: "road_slope")

    # Old snapshot inside v1's window.
    post "/api/v1/hazard_points/#{point.id}/evidence_snapshots",
         params: { evidence_snapshot: { captured_at: "2026-07-10T00:00:00Z", rainfall_mm_24h: 112,
                                        historical_event_count: 0, road_accessible: false } }, as: :json
    old_snap = response.parsed_body["id"]
    post "/api/v1/evidence_snapshots/#{old_snap}/priority", as: :json
    old_body = response.parsed_body
    assert_equal "api-v1", old_body.dig("scoring_policy", "version")
    assert_equal true, old_body["current"]

    # Boundary snapshot inside v2's window, with a business_key, road still closed.
    post "/api/v1/hazard_points/#{point.id}/evidence_snapshots",
         params: { evidence_snapshot: { business_key: "evidence-rds-int-20260802-0000",
                                        captured_at: "2026-08-02T00:00:00Z", rainfall_mm_24h: 210,
                                        historical_event_count: 0, road_accessible: false } }, as: :json
    assert_response :created
    new_snap = response.parsed_body["id"]
    post "/api/v1/evidence_snapshots/#{new_snap}/priority", as: :json
    new_body = response.parsed_body
    assert_equal "api-v2", new_body.dig("scoring_policy", "version")
    assert_equal "blocked", new_body["scheduling_status"]
    assert_operator new_body["total_score"], :>, 0
    assert_equal true, new_body["current"] # latest snapshot -> current

    # The old score still exists, still bound to v1, but no longer current.
    old_score = PriorityScore.find_by!(evidence_snapshot_id: old_snap)
    get "/api/v1/priority_scores/#{old_score.id}/explanation", as: :json
    assert_equal "api-v1", response.parsed_body.dig("scoring_policy", "version")
    assert_equal false, response.parsed_body["current"]
  end

  test "same business_key + same payload is idempotent; different payload is 409" do
    point = create_point!(code: "BK-1", category: "registered_hazard")
    payload = { business_key: "bk-abc", captured_at: "2026-07-10T00:00:00Z",
                rainfall_mm_24h: 95, historical_event_count: 1, road_accessible: true }

    post "/api/v1/hazard_points/#{point.id}/evidence_snapshots",
         params: { evidence_snapshot: payload }, as: :json
    assert_response :created
    first_id = response.parsed_body["id"]

    # Same key + identical payload -> idempotent (same row, created status).
    post "/api/v1/hazard_points/#{point.id}/evidence_snapshots",
         params: { evidence_snapshot: payload }, as: :json
    assert_response :created
    assert_equal first_id, response.parsed_body["id"]

    # Same key + different payload -> conflict.
    post "/api/v1/hazard_points/#{point.id}/evidence_snapshots",
         params: { evidence_snapshot: payload.merge(rainfall_mm_24h: 200) }, as: :json
    assert_response :conflict
    assert_equal "conflicting_business_key", response.parsed_body["error"]
  end

  test "snapshots expose no update or destroy routes" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/api/v1/evidence_snapshots/1", method: :patch)
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/api/v1/evidence_snapshots/1", method: :delete)
    end
  end
end
