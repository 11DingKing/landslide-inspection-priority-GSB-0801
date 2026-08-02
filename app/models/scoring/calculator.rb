module Scoring
  # Pure calculator. Inputs are plain Ruby primitives; output is a frozen
  # Result value. No ActiveRecord, no Time.now, no I/O. The same snapshot +
  # rules tuple always produces an identical Result, which is what makes
  # historical replay and concurrent calculation safe.
  class Calculator
    Result = Struct.new(:total_score, :components, :risk_level,
                        :dispatch_status, :road_accessible, :rules_version,
                        keyword_init: true) do
      def to_h
        {
          total_score: total_score,
          components: components,
          risk_level: risk_level,
          dispatch_status: dispatch_status,
          road_accessible: road_accessible,
          rules_version: rules_version
        }
      end
    end

    Component = Struct.new(:name, :score, :max_score, :reason, keyword_init: true) do
      def to_h
        {
          "name" => name,
          "score" => score,
          "max_score" => max_score,
          "reason" => reason
        }
      end
    end

    def self.call(evidence, rules:, rules_version:, now: nil)
      new(evidence, rules: rules, rules_version: rules_version, now: now).call
    end

    def initialize(evidence, rules:, rules_version:, now:)
      @evidence = evidence
      @rules = rules
      @rules_version = rules_version
      @now = now
    end

    def call
      components = build_components
      total = components.sum(&:score)

      raise "component sum #{total} exceeds max 100" if total > 100

      Result.new(
        total_score: total,
        components: components.map(&:to_h),
        risk_level: risk_level_for(total),
        dispatch_status: @evidence[:road_accessible] ? "available" : "blocked",
        road_accessible: !!@evidence[:road_accessible],
        rules_version: @rules_version
      ).freeze
    end

    private

    def build_components
      [
        rainfall_component,
        historical_component,
        inspection_component,
        point_type_component
      ]
    end

    def rainfall_component
      mm = @evidence[:rainfall_24h_mm].to_f
      hit = @rules.rainfall_thresholds.detect { |t| mm >= t["min_mm"].to_f }
      score = hit ? hit["score"].to_i : 0
      Component.new(
        name: "rainfall_24h",
        score: score,
        max_score: @rules.component_max.fetch("rainfall_24h"),
        reason: "24h rainfall #{mm}mm => bucket starting at #{hit['min_mm']}mm"
      )
    end

    def historical_component
      count = @evidence[:historical_event_count].to_i
      per = @rules.historical_events.fetch("per_event").to_i
      cap = @rules.historical_events.fetch("max").to_i
      score = [count * per, cap].min
      Component.new(
        name: "historical_events",
        score: score,
        max_score: @rules.component_max.fetch("historical_events"),
        reason: "#{count} historical event(s) x #{per} (cap #{cap})"
      )
    end

    def inspection_component
      last = @evidence[:last_inspected_at]
      hours = if last.nil?
                nil
              else
                ((@now - last) / 3600.0)
              end
      cfg = @rules.inspection_recency
      score, bucket =
        if hours.nil?
          [cfg.fetch("never").to_i, "never"]
        elsif hours <= 24
          [cfg.fetch("within_24h").to_i, "within_24h"]
        elsif hours <= cfg.fetch("cutoff_hours").to_i
          [cfg.fetch("within_72h").to_i, "within_72h"]
        else
          [cfg.fetch("older").to_i, "older"]
        end

      Component.new(
        name: "inspection_recency",
        score: score,
        max_score: @rules.component_max.fetch("inspection_recency"),
        reason: if hours.nil?
                  "never inspected => bucket never"
                else
                  "last inspection #{hours.round(1)}h ago => bucket #{bucket}"
                end
      )
    end

    def point_type_component
      kind = @evidence[:kind].to_s
      score = @rules.point_type_weights.fetch(kind, 0).to_i
      Component.new(
        name: "point_type_weight",
        score: score,
        max_score: @rules.component_max.fetch("point_type_weight"),
        reason: "point kind #{kind} has base weight #{score}"
      )
    end

    def risk_level_for(total)
      levels = @rules.risk_levels
      if total >= levels.fetch("critical").to_i
        "critical"
      elsif total >= levels.fetch("high").to_i
        "high"
      elsif total >= levels.fetch("medium").to_i
        "medium"
      else
        "low"
      end
    end
  end
end
