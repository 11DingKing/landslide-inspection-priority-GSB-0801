ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Parallel by process. Threaded concurrency tests live within a single test.
    parallelize(workers: :number_of_processors)

    # Shared builders. No YAML fixtures are used; every test constructs the
    # minimal graph it needs so scoring inputs stay explicit.
    def build_baseline_definition
      {
        "rainfall" => { "thresholds" => [[0, 0], [50, 8], [80, 16], [100, 22], [120, 28], [150, 34], [180, 40]] },
        "history"  => { "thresholds" => [[0, 0], [1, 10], [2, 18], [3, 25]] },
        "recency"  => { "never_inspected" => 20, "thresholds" => [[0, 0], [7, 3], [30, 6], [90, 10], [180, 14], [365, 18]] },
        "exposure" => { "default" => 0, "by_category" => { "cut_slope_housing" => 15, "road_slope" => 10, "registered_hazard" => 7 } },
        "risk_bands" => [[0, "low"], [35, "moderate"], [60, "high"], [80, "extreme"]]
      }
    end

    def create_policy!(version:, effective_from:, effective_until: nil, definition: nil, publish: true)
      policy = ScoringPolicy.create!(
        version: version,
        effective_from: effective_from,
        effective_until: effective_until,
        definition: definition || build_baseline_definition
      )
      policy.publish! if publish
      policy
    end

    def create_point!(code:, category: "registered_hazard", last_inspected_at: nil)
      HazardPoint.create!(
        code: code, name: "point #{code}", category: category,
        last_inspected_at: last_inspected_at
      )
    end

    def create_snapshot!(point, captured_at: Time.current, rainfall: 0, history: 0, road_accessible: true, last_inspected_at: nil)
      point.evidence_snapshots.create!(
        captured_at: captured_at,
        rainfall_mm_24h: rainfall,
        historical_event_count: history,
        road_accessible: road_accessible,
        point_last_inspected_at: last_inspected_at
      )
    end
  end
end
