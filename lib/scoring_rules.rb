module ScoringRules
  module V1
    def self.rules
      {
        "items" => [
          {
            "key" => "rainfall_24h",
            "name" => "24小时降水",
            "field" => "rainfall_24h_mm",
            "type" => "numeric_tier",
            "max" => 40,
            "tiers" => [
              { "min" => 0, "max" => 50, "score" => 0 },
              { "min" => 50, "max" => 100, "score" => 10 },
              { "min" => 100, "max" => 150, "score" => 25 },
              { "min" => 150, "max" => 200, "score" => 35 },
              { "min" => 200, "max" => nil, "score" => 40 }
            ]
          },
          {
            "key" => "historical_events",
            "name" => "历史事件次数",
            "field" => "historical_event_count",
            "type" => "numeric_tier",
            "max" => 25,
            "tiers" => [
              { "min" => 0, "max" => 1, "score" => 0 },
              { "min" => 1, "max" => 2, "score" => 12 },
              { "min" => 2, "max" => nil, "score" => 25 }
            ]
          },
          {
            "key" => "point_type_risk",
            "name" => "点位类型基础风险",
            "field" => "point_type",
            "type" => "categorical",
            "max" => 20,
            "values" => {
              "cut_slope_building" => 20,
              "road_slope" => 12,
              "registered_hazard" => 8
            }
          },
          {
            "key" => "inspection_recency",
            "name" => "巡查时效",
            "type" => "inspection_recency",
            "max" => 15,
            "values" => {
              "never" => 15,
              "today" => 0,
              "overdue" => 15
            }
          }
        ],
        "risk_levels" => [
          { "min" => 0, "max" => 30, "level" => "low" },
          { "min" => 30, "max" => 60, "level" => "medium" },
          { "min" => 60, "max" => 80, "level" => "high" },
          { "min" => 80, "max" => nil, "level" => "critical" }
        ]
      }
    end
  end

  def self.version(version = 1)
    case version
    when 1 then V1.rules
    else V1.rules
    end
  end
end
