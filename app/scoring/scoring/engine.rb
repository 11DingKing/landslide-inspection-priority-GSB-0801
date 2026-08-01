module Scoring
  # Immutable value object describing one component's contribution. Kept as a
  # plain struct so it serialises cleanly into the explanation payload.
  Component = Data.define(:name, :score, :max, :basis) do
    def to_h
      { name: name, score: score, max: max, basis: basis }
    end
  end

  # The one and only place scoring rules live.
  #
  # The engine is a pure function of (snapshot facts, policy definition). It has
  # no knowledge of ActiveRecord, HTTP, or persistence, which is what makes a
  # historical snapshot replayable against any policy version and keeps scoring
  # rules out of controllers and callbacks.
  #
  # LOCKED contract (must not drift):
  #   * component names ....... rainfall, history, recency, exposure
  #   * component ranges ...... 0..40, 0..25, 0..20, 0..15
  #   * total ................. exact integer sum of the four, 0..100
  #   * road inaccessibility .. affects scheduling_status ONLY, never the scores
  #                             or the risk level
  class Engine
    COMPONENT_MAX = {
      "rainfall" => 40,
      "history"  => 25,
      "recency"  => 20,
      "exposure" => 15
    }.freeze

    Result = Data.define(
      :components, :total_score, :risk_level, :scheduling_status,
      :road_accessible, :policy_version
    ) do
      def rainfall_score = component_score("rainfall")
      def history_score  = component_score("history")
      def recency_score  = component_score("recency")
      def exposure_score = component_score("exposure")

      def blocked? = scheduling_status == "blocked"

      def component_score(name)
        components.find { |c| c.name == name }.score
      end

      def to_h
        {
          total_score: total_score,
          risk_level: risk_level,
          scheduling_status: scheduling_status,
          road_accessible: road_accessible,
          policy_version: policy_version,
          components: components.map(&:to_h)
        }
      end
    end

    def initialize(definition)
      @definition = definition.deep_stringify_keys
    end

    # facts: an object responding to rainfall_mm_24h, historical_event_count,
    # road_accessible, point_last_inspected_at, captured_at, and (via
    # hazard_point) category. EvidenceSnapshot satisfies this directly.
    def score(facts:, category:, policy_version:)
      components = [
        rainfall_component(facts),
        history_component(facts),
        recency_component(facts),
        exposure_component(category)
      ]

      total = components.sum(&:score)
      # Intrinsic severity is derived from the intrinsic total. Road access is
      # deliberately NOT an input here.
      risk = risk_level_for(total)

      # Scheduling is the only place road access matters. A blocked road never
      # lowers the score or risk; it just routes the point differently.
      scheduling = facts_road_accessible?(facts) ? "schedulable" : "blocked"

      Result.new(
        components: components,
        total_score: total,
        risk_level: risk,
        scheduling_status: scheduling,
        road_accessible: facts_road_accessible?(facts),
        policy_version: policy_version
      )
    end

    private

    attr_reader :definition

    def rainfall_component(facts)
      mm = BigDecimal(facts.rainfall_mm_24h.to_s)
      table = definition.dig("rainfall", "thresholds") || []
      score = piecewise(table, mm)
      Component.new(
        name: "rainfall",
        score: clamp(score, "rainfall"),
        max: COMPONENT_MAX["rainfall"],
        basis: "24h rainfall #{mm.to_s('F')} mm"
      )
    end

    def history_component(facts)
      count = facts.historical_event_count.to_i
      table = definition.dig("history", "thresholds") || []
      score = piecewise(table, count)
      Component.new(
        name: "history",
        score: clamp(score, "history"),
        max: COMPONENT_MAX["history"],
        basis: "#{count} historical event(s)"
      )
    end

    def recency_component(facts)
      last = facts.point_last_inspected_at
      never_score = definition.dig("recency", "never_inspected") || COMPONENT_MAX["recency"]

      if last.nil?
        return Component.new(
          name: "recency",
          score: clamp(never_score, "recency"),
          max: COMPONENT_MAX["recency"],
          basis: "never inspected"
        )
      end

      days = ((facts.captured_at - last) / 86_400.0).floor
      days = 0 if days.negative?
      table = definition.dig("recency", "thresholds") || []
      score = piecewise(table, days)
      Component.new(
        name: "recency",
        score: clamp(score, "recency"),
        max: COMPONENT_MAX["recency"],
        basis: "#{days} day(s) since last inspection"
      )
    end

    def exposure_component(category)
      map = definition.dig("exposure", "by_category") || {}
      score = map.fetch(category.to_s, definition.dig("exposure", "default") || 0)
      Component.new(
        name: "exposure",
        score: clamp(score, "exposure"),
        max: COMPONENT_MAX["exposure"],
        basis: "category #{category}"
      )
    end

    def risk_level_for(total)
      bands = definition["risk_bands"] || default_risk_bands
      # bands: array of [min_total, level], evaluated high-to-low.
      bands.sort_by { |min, _| -min.to_i }
           .each { |min, level| return level if total >= min.to_i }
      "low"
    end

    def default_risk_bands
      [[80, "extreme"], [60, "high"], [35, "moderate"], [0, "low"]]
    end

    # Piecewise step function: given [[threshold, points], ...], return the
    # points of the highest threshold that `value` reaches. Deterministic and
    # order-independent because we sort descending by threshold.
    def piecewise(table, value)
      table.map { |min, pts| [BigDecimal(min.to_s), pts.to_i] }
           .sort_by { |min, _| -min }
           .each { |min, pts| return pts if BigDecimal(value.to_s) >= min }
      0
    end

    def clamp(score, name)
      s = score.to_i
      s.clamp(0, COMPONENT_MAX.fetch(name))
    end

    def facts_road_accessible?(facts)
      facts.road_accessible
    end
  end
end
