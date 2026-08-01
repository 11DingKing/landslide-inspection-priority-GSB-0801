FactoryBot.define do
  factory :hazard_point do
    sequence(:name) { |n| "隐患点 #{n}" }
    point_type { "registered_hazard" }
    road_accessible { true }
    historical_event_count { 0 }
    latest_rainfall_24h_mm { 0.0 }
    last_inspected_at { nil }
    location { "测试位置" }

    trait :cut_slope_building do
      point_type { "cut_slope_building" }
      historical_event_count { 2 }
      latest_rainfall_24h_mm { 186.0 }
    end

    trait :road_slope_closed do
      point_type { "road_slope" }
      road_accessible { false }
      historical_event_count { 0 }
      latest_rainfall_24h_mm { 112.0 }
      last_inspected_at { 2.days.ago }
    end

    trait :registered_hazard do
      point_type { "registered_hazard" }
      historical_event_count { 1 }
      latest_rainfall_24h_mm { 95.0 }
      last_inspected_at { Time.current }
    end
  end
end
