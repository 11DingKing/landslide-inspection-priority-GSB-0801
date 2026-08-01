FactoryBot.define do
  factory :evidence_snapshot do
    hazard_point
    scoring_strategy
    snapshot_at { Time.current }
    rainfall_24h_mm { 50.0 }
    historical_event_count { 0 }
    point_type { "registered_hazard" }
    road_status { "accessible" }
    last_inspected_at { nil }
    total_score { 18 }
    risk_level { "low" }
    dispatch_status { "schedulable" }
    score_breakdown do
      [
        { "key" => "rainfall_24h", "name" => "24小时降水", "score" => 10, "max" => 40, "reason" => "r" },
        { "key" => "historical_events", "name" => "历史事件次数", "score" => 0, "max" => 25, "reason" => "r" },
        { "key" => "point_type_risk", "name" => "点位类型基础风险", "score" => 8, "max" => 20, "reason" => "r" },
        { "key" => "inspection_recency", "name" => "巡查时效", "score" => 0, "max" => 15, "reason" => "r" }
      ]
    end
    explanation { { "summary" => "总分 18" } }
  end
end
