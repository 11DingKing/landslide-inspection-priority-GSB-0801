# frozen_string_literal: true

require "test_helper"

module Scoring
  class EngineTest < ActiveSupport::TestCase
    BASE_EVIDENCE = {
      rainfall_24h_mm: 0, historical_event_count: 0,
      last_inspected_at: nil, road_accessible: true,
      captured_at: Time.zone.parse("2026-08-01 08:00:00")
    }.freeze

    def score(evidence = {}, rules = RULES_V1)
      Engine.score(evidence: BASE_EVIDENCE.merge(evidence), rules: rules)
    end

    test "components sum strictly equals total score" do
      [0, 20, 50, 95, 112, 186, 500].each do |mm|
        (0..3).each do |events|
          [nil, 1.day.ago, 90.days.ago].each do |last|
            result = score(rainfall_24h_mm: mm, historical_event_count: events, last_inspected_at: last)
            assert_equal result.components.values.sum, result.total_score
            assert_kind_of Integer, result.total_score
          end
        end
      end
    end

    test "component names and ranges are locked" do
      assert_equal %w[rainfall_24h historical_events inspection_recency],
                   Engine::COMPONENTS.keys
      assert_equal({ "rainfall_24h" => 40, "historical_events" => 30, "inspection_recency" => 30 },
                   Engine::COMPONENTS)
      assert_equal (0..100), Engine::TOTAL_RANGE
    end

    test "rules payload may not exceed a locked component range" do
      bad = RULES_V1.deep_merge("rainfall_24h" => { "thresholds" => [{ "gte_mm" => 100, "score" => 41 }] })
      assert_raises(Engine::InvalidRules) { Engine.validate_rules!(bad) }
    end

    test "rules payload may not add unknown sections" do
      bad = RULES_V1.merge("slope_angle" => { "per_degree" => 1 })
      assert_raises(Engine::InvalidRules) { Engine.validate_rules!(bad) }
    end

    test "rules payload must be complete" do
      bad = RULES_V1.except("historical_events")
      assert_raises(Engine::InvalidRules) { Engine.validate_rules!(bad) }
    end

    test "seed scenario: cut-slope building point scores 100 high" do
      result = score(rainfall_24h_mm: 186, historical_event_count: 2, last_inspected_at: nil)
      assert_equal({ "rainfall_24h" => 40, "historical_events" => 30, "inspection_recency" => 30 },
                   result.components)
      assert_equal 100, result.total_score
      assert_equal "high", result.risk_level
      assert_equal "schedulable", result.scheduling_status
    end

    test "seed scenario: closed road slope keeps medium risk and is only blocked" do
      result = score(rainfall_24h_mm: 112, historical_event_count: 0,
                     last_inspected_at: 90.days.before(BASE_EVIDENCE[:captured_at]),
                     road_accessible: false)
      assert_equal 55, result.total_score
      assert_equal "medium", result.risk_level # risk preserved, NOT lowered to 0
      assert_equal "blocked", result.scheduling_status
    end

    test "inaccessibility changes scheduling only, never the score" do
      open = score(rainfall_24h_mm: 112, last_inspected_at: 90.days.ago, road_accessible: true)
      closed = score(rainfall_24h_mm: 112, last_inspected_at: 90.days.ago, road_accessible: false)
      assert_equal open.total_score, closed.total_score
      assert_equal open.risk_level, closed.risk_level
      assert_equal "schedulable", open.scheduling_status
      assert_equal "blocked", closed.scheduling_status
    end

    test "seed scenario: registered hazard with same-day inspection scores low" do
      result = score(rainfall_24h_mm: 95, historical_event_count: 1,
                     last_inspected_at: BASE_EVIDENCE[:captured_at])
      assert_equal({ "rainfall_24h" => 20, "historical_events" => 15, "inspection_recency" => 0 },
                   result.components)
      assert_equal 35, result.total_score
      assert_equal "low", result.risk_level
    end

    test "recency buckets: never inspected, stale, same-day" do
      assert_equal 30, score(last_inspected_at: nil).components["inspection_recency"]
      assert_equal 25, score(last_inspected_at: 95.days.ago).components["inspection_recency"]
      assert_equal 15, score(last_inspected_at: 45.days.ago).components["inspection_recency"]
      assert_equal 5,  score(last_inspected_at: 10.days.ago).components["inspection_recency"]
      assert_equal 0,  score(last_inspected_at: Time.current).components["inspection_recency"]
    end

    test "historical events are capped by the strategy" do
      assert_equal 30, score(historical_event_count: 5).components["historical_events"]
    end

    test "engine is deterministic and replayable" do
      evidence = { rainfall_24h_mm: 186, historical_event_count: 2, last_inspected_at: nil }
      first = score(evidence)
      second = score(evidence)
      assert_equal first, second
    end
  end
end
