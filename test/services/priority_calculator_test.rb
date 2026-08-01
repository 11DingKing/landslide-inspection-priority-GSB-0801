# frozen_string_literal: true

require "test_helper"

class PriorityCalculatorTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    clean_tables!
  end

  test "computes and persists a score record from the applicable strategy" do
    strategy = build_strategy(version: 1, status: "published")
    point = build_point("CALC-1")
    snapshot = build_snapshot(point, rainfall_24h_mm: 186, historical_event_count: 2,
                              captured_at: 1.hour.ago)

    record = PriorityCalculator.call(snapshot: snapshot)

    assert record.persisted?
    assert_equal strategy.id, record.strategy_version_id
    assert_equal 100, record.total_score
    assert_equal record.components.values.sum, record.total_score
    assert_equal "high", record.risk_level
  end

  test "concurrent computation of the same snapshot yields exactly one record" do
    build_strategy(version: 1, status: "published")
    snapshot = build_snapshot(build_point("CALC-2"), rainfall_24h_mm: 95,
                              historical_event_count: 1, captured_at: 1.hour.ago)

    results = Concurrent::Array.new
    threads = 4.times.map do
      Thread.new { results << PriorityCalculator.call(snapshot: snapshot) }
    end
    threads.each(&:join)

    assert_equal 1, ScoreRecord.where(evidence_snapshot: snapshot).count
    totals = results.map(&:total_score).uniq
    assert_equal [65], totals # 20 (rain) + 15 (history) + 30 (never inspected)
    assert_equal 1, results.map(&:id).uniq.size
  end

  test "replaying an old snapshot reproduces the original decision exactly" do
    boundary = Time.current + 1.day
    v1 = build_strategy(version: 1, to: boundary, status: "published")
    point = build_point("CALC-3")
    captured = Time.zone.parse("2026-08-01 03:00:00")
    snapshot = build_snapshot(point, rainfall_24h_mm: 186, historical_event_count: 2,
                              last_inspected_at: nil, captured_at: captured)

    original = PriorityCalculator.call(snapshot: snapshot)

    # A new strategy is published afterwards for FUTURE evidence only.
    new_rules = RULES_V1.deep_merge("rainfall_24h" => { "thresholds" => [{ "gte_mm" => 150, "score" => 35 }] })
    build_strategy(version: 2, rules: new_rules, from: boundary, status: "published")

    replay = PriorityCalculator.call(snapshot: snapshot)

    assert_equal original.id, replay.id
    assert_equal v1.id, replay.strategy_version_id
    assert_equal 100, replay.total_score # yesterday's judgment unchanged
    assert_equal original.components, replay.components
  end

  test "comparative replay of an old snapshot under an explicit newer version" do
    boundary = Time.current + 1.day
    build_strategy(version: 1, to: boundary, status: "published")
    v2_rules = RULES_V1.deep_merge("historical_events" => { "per_event" => 10, "cap_events" => 2 })
    v2 = build_strategy(version: 2, rules: v2_rules,
                        from: boundary, status: "published")
    snapshot = build_snapshot(build_point("CALC-4"), rainfall_24h_mm: 186,
                              historical_event_count: 2, captured_at: 1.hour.ago)

    original = PriorityCalculator.call(snapshot: snapshot)
    replayed = PriorityCalculator.call(snapshot: snapshot, strategy_version: v2)

    assert_not_equal original.id, replayed.id
    assert_equal v2.id, replayed.strategy_version_id
    assert_equal 90, replayed.total_score # 40 + 20 + 30
    assert_equal 2, ScoreRecord.where(evidence_snapshot: snapshot).count
  end

  test "raises when no published strategy covers the snapshot time" do
    build_strategy(version: 1, from: Time.current + 1.day, status: "published")
    snapshot = build_snapshot(build_point("CALC-5"), captured_at: 1.hour.ago)

    assert_raises(PriorityCalculator::NoApplicableStrategy) do
      PriorityCalculator.call(snapshot: snapshot)
    end
  end

  test "only one current score per hazard point" do
    build_strategy(version: 1, status: "published")
    point = build_point("CALC-6")
    old_snapshot = build_snapshot(point, rainfall_24h_mm: 30, captured_at: 2.hours.ago)
    new_snapshot = build_snapshot(point, rainfall_24h_mm: 186, historical_event_count: 2,
                                  captured_at: 1.hour.ago)

    old_record = PriorityCalculator.call(snapshot: old_snapshot)
    new_record = PriorityCalculator.call(snapshot: new_snapshot)

    assert_not old_record.reload.is_current
    assert new_record.reload.is_current
    assert_equal 1, ScoreRecord.current.where(hazard_point: point).count
  end
end
