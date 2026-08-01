# frozen_string_literal: true

require "test_helper"

class StrategyVersionsApiTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  teardown do
    StrategyVersion.delete_all
  end

  test "create and publish a strategy version" do
    post "/api/v1/strategy_versions", params: {
      strategy_version: {
        version: 1,
        effective_from: "2026-01-01T00:00:00+08:00",
        rules: RULES_V1
      },
      publish: true
    }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal "published", body["status"]
    assert_equal Time.zone.parse("2026-01-01T00:00:00+08:00"), Time.iso8601(body["effective_from"])
    assert_nil body["effective_to"]
  end

  test "publishing a candidate overlapping a published range returns 409" do
    build_strategy(version: 1, from: Time.zone.parse("2026-01-01"), status: "published")

    post "/api/v1/strategy_versions", params: {
      strategy_version: {
        version: 2,
        effective_from: "2026-06-01T00:00:00+08:00",
        rules: RULES_V1
      },
      publish: true
    }, as: :json

    assert_response :conflict
    assert_match(/already covers/, response.parsed_body["error"])
    assert_equal 1, StrategyVersion.published.count
  end

  test "rules violating the locked schema return 422" do
    bad_rules = RULES_V1.merge("historical_events" => { "per_event" => 31, "cap_events" => 1 })

    post "/api/v1/strategy_versions", params: {
      strategy_version: { version: 3, effective_from: "2026-01-01T00:00:00+08:00", rules: bad_rules }
    }, as: :json

    assert_response :unprocessable_entity
  end
end
