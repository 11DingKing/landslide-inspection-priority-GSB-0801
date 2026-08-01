require "test_helper"

class Api::V1::PriorityFlowTest < ActionDispatch::IntegrationTest
  setup do
    @policy = create_policy!(version: "api-v1", effective_at: Time.utc(2026, 7, 1))
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
    post "/api/v1/scoring_policies",
         params: { scoring_policy: { version: "api-dup", effective_at: "2026-07-01T00:00:00Z",
                                     definition: build_baseline_definition } },
         as: :json
    assert_response :created
    dup_id = response.parsed_body["id"]

    post "/api/v1/scoring_policies/#{dup_id}/publish", as: :json
    assert_response :conflict
    assert_equal "overlapping_policy", response.parsed_body["error"]
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
