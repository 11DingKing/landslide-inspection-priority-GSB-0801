module Scoring
  # Immutable value object that holds the tunable parameters of a scoring
  # strategy. Everything is stored as plain integers / strings so that a
  # rules_json document can be round-tripped through JSON without drift.
  class Rules
    COMPONENT_NAMES = %w[
      rainfall_24h
      historical_events
      inspection_recency
      point_type_weight
    ].freeze

    DEFAULT_RULES = {
      "rainfall_thresholds" => [
        { "min_mm" => 150, "score" => 40 },
        { "min_mm" => 100, "score" => 30 },
        { "min_mm" => 50,  "score" => 18 },
        { "min_mm" => 0,   "score" => 5  }
      ],
      "historical_events" => {
        "per_event" => 8,
        "max"       => 20
      },
      "inspection_recency" => {
        "never"        => 20,
        "within_24h"   => 0,
        "within_72h"   => 8,
        "older"        => 15,
        "cutoff_hours" => 72
      },
      "point_type_weights" => {
        "cut_slope_building" => 20,
        "road_slope"         => 12,
        "registered_hazard"  => 8
      },
      "risk_levels" => {
        "critical" => 75,
        "high"     => 55,
        "medium"   => 35
      },
      "component_max" => {
        "rainfall_24h"       => 40,
        "historical_events"  => 20,
        "inspection_recency" => 20,
        "point_type_weight"  => 20
      }
    }.freeze

    attr_reader :rainfall_thresholds, :historical_events, :inspection_recency,
                :point_type_weights, :risk_levels, :component_max

    def initialize(hash)
      data = DEFAULT_RULES.deep_dup
      data.deep_merge!(hash.deep_dup) if hash.is_a?(Hash)
      @rainfall_thresholds = data.fetch("rainfall_thresholds").freeze
      @historical_events   = data.fetch("historical_events").freeze
      @inspection_recency  = data.fetch("inspection_recency").freeze
      @point_type_weights  = data.fetch("point_type_weights").freeze
      @risk_levels         = data.fetch("risk_levels").freeze
      @component_max       = data.fetch("component_max").freeze
      freeze
    end

    def self.from_hash(hash)
      new(hash || {})
    end

    def self.default
      new(DEFAULT_RULES.deep_dup)
    end

    def to_h
      {
        "rainfall_thresholds" => rainfall_thresholds.map(&:dup),
        "historical_events"   => historical_events.dup,
        "inspection_recency"  => inspection_recency.dup,
        "point_type_weights"  => point_type_weights.dup,
        "risk_levels"         => risk_levels.dup,
        "component_max"       => component_max.dup
      }
    end

    def max_total
      component_max.values.sum
    end
  end
end
