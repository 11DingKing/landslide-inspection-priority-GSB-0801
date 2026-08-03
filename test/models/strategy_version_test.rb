# frozen_string_literal: true

require "test_helper"

class StrategyVersionTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    StrategyVersion.delete_all
  end

  test "publish resolves the unique version covering a snapshot time" do
    build_strategy(version: 1, from: Time.zone.parse("2026-01-01"), to: Time.zone.parse("2026-07-01"), status: "published")
    build_strategy(version: 2, from: Time.zone.parse("2026-07-01"), status: "published")

    assert_equal 1, StrategyVersion.applicable_to(Time.zone.parse("2026-03-01")).version
    assert_equal 2, StrategyVersion.applicable_to(Time.zone.parse("2026-08-01")).version
  end

  test "overlapping published ranges are rejected" do
    build_strategy(version: 1, from: Time.zone.parse("2026-01-01"), status: "published")
    overlap = build_strategy(version: 2, from: Time.zone.parse("2026-06-01"))

    error = assert_raises(ActiveRecord::StatementInvalid) { overlap.publish! }
    assert_match(/strategy_versions_no_published_overlap/, error.message)
    assert_equal 1, StrategyVersion.published.count
  end

  test "adjacent (non-overlapping) ranges are accepted" do
    boundary = Time.zone.parse("2026-07-01 00:00:00")
    build_strategy(version: 1, from: Time.zone.parse("2026-01-01"), to: boundary, status: "published")
    build_strategy(version: 2, from: boundary, status: "published")
    assert_equal 2, StrategyVersion.published.count
  end

  test "concurrent publish of two candidates at the same moment elects exactly one" do
    moment = Time.zone.parse("2026-08-01 00:00:00")
    candidate_a = build_strategy(version: 11, from: moment)
    candidate_b = build_strategy(version: 12, from: moment)

    barrier = Queue.new
    results = Concurrent::Array.new
    threads = [candidate_a, candidate_b].map do |candidate|
      Thread.new do
        barrier.pop # both threads release at the same time
        begin
          candidate.publish!
          results << :ok
        rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid
          results << :conflict
        end
      end
    end
    2.times { barrier.push(true) }
    threads.each(&:join)

    assert_equal %i[conflict ok].sort, results.sort
    assert_equal 1, StrategyVersion.published.count
  end

  test "rules outside the locked schema cannot be persisted" do
    bad = RULES_V1.merge("rainfall_24h" => { "thresholds" => [{ "gte_mm" => 10, "score" => 99 }] })
    version = StrategyVersion.new(version: 3, rules: bad,
                                  effective_range: StrategyVersion.compose_range(Time.current, nil))
    assert_not version.valid?
    assert_match(/locked range/, version.errors[:rules].join)
  end
end
