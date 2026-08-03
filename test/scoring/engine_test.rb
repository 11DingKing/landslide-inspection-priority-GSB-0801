require "test_helper"

class Scoring::EngineTest < ActiveSupport::TestCase
  # Minimal facts double so the engine can be tested without touching the DB.
  Facts = Struct.new(
    :rainfall_mm_24h, :historical_event_count, :road_accessible,
    :point_last_inspected_at, :captured_at, keyword_init: true
  )

  setup do
    @engine = Scoring::Engine.new(build_baseline_definition)
    @now = Time.utc(2026, 8, 1, 12, 0, 0)
  end

  def score(facts:, category:)
    @engine.score(facts: facts, category: category, policy_version: "test")
  end

  test "component names and ranges are locked" do
    assert_equal({ "rainfall" => 40, "history" => 25, "recency" => 20, "exposure" => 15 },
                 Scoring::Engine::COMPONENT_MAX)
  end

  test "cut-slope housing: 186mm, 2 events, never inspected" do
    facts = Facts.new(rainfall_mm_24h: 186, historical_event_count: 2,
                      road_accessible: true, point_last_inspected_at: nil, captured_at: @now)
    r = score(facts: facts, category: "cut_slope_housing")
    assert_equal 40, r.rainfall_score
    assert_equal 18, r.history_score
    assert_equal 20, r.recency_score # never inspected
    assert_equal 15, r.exposure_score
    assert_equal 93, r.total_score
    assert_equal "extreme", r.risk_level
    assert_equal "schedulable", r.scheduling_status
  end

  test "road slope: 112mm, road closed, inspected long ago -> blocked but risk preserved" do
    facts = Facts.new(rainfall_mm_24h: 112, historical_event_count: 0,
                      road_accessible: false, point_last_inspected_at: @now - 400 * 86_400, captured_at: @now)
    r = score(facts: facts, category: "road_slope")
    assert_equal 22, r.rainfall_score # 112mm falls in the >=100 band
    assert_equal 0, r.history_score
    assert_equal 18, r.recency_score # >= 365 days
    assert_equal 10, r.exposure_score
    assert_equal 50, r.total_score
    assert_equal "moderate", r.risk_level
    # The decisive invariant: road closed only changes scheduling.
    assert_equal "blocked", r.scheduling_status
    refute_equal 0, r.total_score
  end

  test "registered hazard: 95mm, 1 event, inspected today" do
    facts = Facts.new(rainfall_mm_24h: 95, historical_event_count: 1,
                      road_accessible: true, point_last_inspected_at: @now, captured_at: @now)
    r = score(facts: facts, category: "registered_hazard")
    assert_equal 16, r.rainfall_score
    assert_equal 10, r.history_score
    assert_equal 0, r.recency_score # inspected today
    assert_equal 7, r.exposure_score
    assert_equal 33, r.total_score
    assert_equal "low", r.risk_level
  end

  test "components always sum exactly to total across a wide input sweep" do
    categories = HazardPoint::CATEGORIES
    [0, 49, 50, 80, 100, 120, 150, 179, 180, 300].each do |mm|
      [0, 1, 2, 3, 5].each do |events|
        [nil, @now, @now - 10 * 86_400, @now - 400 * 86_400].each do |last|
          categories.each do |cat|
            facts = Facts.new(rainfall_mm_24h: mm, historical_event_count: events,
                              road_accessible: true, point_last_inspected_at: last, captured_at: @now)
            r = score(facts: facts, category: cat)
            sum = r.rainfall_score + r.history_score + r.recency_score + r.exposure_score
            assert_equal r.total_score, sum, "sum mismatch for mm=#{mm} events=#{events} cat=#{cat}"
            assert r.total_score.between?(0, 100)
          end
        end
      end
    end
  end

  test "road accessibility never changes scores, only scheduling" do
    base = { rainfall_mm_24h: 186, historical_event_count: 2, point_last_inspected_at: nil, captured_at: @now }
    open = score(facts: Facts.new(road_accessible: true, **base), category: "cut_slope_housing")
    closed = score(facts: Facts.new(road_accessible: false, **base), category: "cut_slope_housing")

    assert_equal open.total_score, closed.total_score
    assert_equal open.risk_level, closed.risk_level
    assert_equal "schedulable", open.scheduling_status
    assert_equal "blocked", closed.scheduling_status
  end
end
