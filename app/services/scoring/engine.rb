# frozen_string_literal: true

module Scoring
  # Pure, deterministic scoring engine.
  #
  # Invariants enforced here (and verified by the test-suite):
  #   * Component names and their score ranges are LOCKED. A strategy version
  #     may tune thresholds and weights, but can never rename a component,
  #     add a new one, or exceed a component's locked maximum.
  #   * The total score is always exactly the sum of the component scores
  #     (integer arithmetic, computed as the literal sum).
  #   * Road inaccessibility NEVER lowers risk. It only flips the scheduling
  #     status to "blocked" while the risk level is preserved.
  #   * The engine is pure: no database access, no clock access beyond the
  #     evidence supplied, no callbacks. The same (evidence, rules) pair
  #     always yields the same result, which makes replays byte-identical.
  class Engine
    # Locked component registry: name => maximum score (range is 0..max).
    COMPONENTS = {
      "rainfall_24h"        => 40,
      "historical_events"   => 30,
      "inspection_recency"  => 30
    }.freeze

    TOTAL_RANGE = (0..COMPONENTS.values.sum).freeze
    RISK_LEVELS = %w[high medium low].freeze
    SCHEDULING_STATUSES = %w[schedulable blocked].freeze

    Result = Data.define(:components, :total_score, :risk_level, :scheduling_status)

    class InvalidRules < StandardError; end

    # Validates a strategy rules payload against the locked component schema.
    # Raises InvalidRules on any deviation. Called by StrategyVersion before
    # persistence, so every persisted version is guaranteed scorable.
    def self.validate_rules!(rules)
      raise InvalidRules, "rules must be a Hash" unless rules.is_a?(Hash)

      rules = rules.deep_stringify_keys
      unknown = rules.keys - (COMPONENTS.keys + %w[risk_levels])
      raise InvalidRules, "unknown rule sections: #{unknown.join(', ')}" if unknown.any?

      COMPONENTS.each_key do |name|
        section = rules[name]
        raise InvalidRules, "missing rule section: #{name}" if section.nil?

        max = COMPONENTS[name]
        achievable = case name
                     when "rainfall_24h"
                       section["thresholds"].map { |t| Integer(t.fetch("score")) }.max || 0
                     when "historical_events"
                       Integer(section.fetch("per_event")) * Integer(section.fetch("cap_events"))
                     when "inspection_recency"
                       stale = section["stale_days"].map { |t| Integer(t.fetch("score")) }
                       [Integer(section.fetch("never")), stale.max || 0, Integer(section.fetch("fresh", 0))].max
                     end
        if achievable.negative? || achievable > max
          raise InvalidRules, "component #{name} exceeds locked range 0..#{max}"
        end
      end

      levels = rules["risk_levels"]
      raise InvalidRules, "missing rule section: risk_levels" if levels.nil?
      levels.each do |entry|
        unless RISK_LEVELS.include?(entry["level"]) && entry["min_total"].is_a?(Integer)
          raise InvalidRules, "invalid risk_levels entry: #{entry.inspect}"
        end
      end

      true
    end

    # evidence: { rainfall_24h_mm:, historical_event_count:, last_inspected_at:,
    #             road_accessible:, captured_at: }
    # rules: a validated strategy rules payload.
    # Returns a Result. Pure function.
    def self.score(evidence:, rules:)
      rules = rules.deep_stringify_keys

      components = {
        "rainfall_24h"       => rainfall_score(evidence[:rainfall_24h_mm], rules["rainfall_24h"]),
        "historical_events"  => historical_score(evidence[:historical_event_count], rules["historical_events"]),
        "inspection_recency" => recency_score(evidence[:last_inspected_at], evidence[:captured_at], rules["inspection_recency"])
      }

      # Guarantee the locked ranges hold even for a hand-crafted payload.
      components.each do |name, value|
        max = COMPONENTS.fetch(name)
        raise InvalidRules, "component #{name}=#{value} outside 0..#{max}" if value.negative? || value > max
      end

      total = components.values.sum
      risk_level = rules["risk_levels"]
                   .sort_by { |e| -e.fetch("min_total") }
                   .find { |e| total >= e.fetch("min_total") }
                   &.fetch("level") || "low"

      Result.new(
        components: components,
        total_score: total,
        risk_level: risk_level,
        # Inaccessibility never touches the score; it only blocks scheduling.
        scheduling_status: evidence[:road_accessible] ? "schedulable" : "blocked"
      )
    end

    def self.rainfall_score(rainfall_mm, section)
      mm = BigDecimal(rainfall_mm.to_s)
      section["thresholds"]
        .sort_by { |t| -BigDecimal(t.fetch("gte_mm").to_s) }
        .find { |t| mm >= BigDecimal(t.fetch("gte_mm").to_s) }
        &.fetch("score") || 0
    end
    private_class_method :rainfall_score

    def self.historical_score(count, section)
      per_event = Integer(section.fetch("per_event"))
      cap = Integer(section.fetch("cap_events"))
      [Integer(count), cap].min * per_event
    end
    private_class_method :historical_score

    def self.recency_score(last_inspected_at, captured_at, section)
      return Integer(section.fetch("never")) if last_inspected_at.nil?

      days = (captured_at.to_time - last_inspected_at.to_time) / 86_400.0
      return Integer(section.fetch("fresh", 0)) if days <= 1.0

      section["stale_days"]
        .sort_by { |t| -Integer(t.fetch("gte_days")) }
        .find { |t| days >= Integer(t.fetch("gte_days")) }
        &.fetch("score") || Integer(section.fetch("fresh", 0))
    end
    private_class_method :recency_score
  end
end
