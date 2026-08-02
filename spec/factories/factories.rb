FactoryBot.define do
  factory :hazard_point do
    sequence(:name) { |n| "HP-#{n}" }
    kind { "registered_hazard" }
    road_accessible { true }

    trait :cut_slope do
      kind { "cut_slope_building" }
    end

    trait :road_slope do
      kind { "road_slope" }
    end

    trait :blocked do
      road_accessible { false }
    end
  end

  factory :evidence_snapshot do
    hazard_point
    sequence(:snapshot_time) { |n| n.hours.ago }
    rainfall_24h_mm { 50.0 }
    historical_event_count { 0 }
    last_inspected_at { nil }
    road_accessible { |s| s.hazard_point.road_accessible }
  end

  factory :scoring_strategy do
    sequence(:name) { |n| "Strategy #{n}" }
    sequence(:version_code) { |n| "v#{n}.0.0" }
    status { "published" }
    effective_at { 1.month.ago }
    published_at { 1.month.ago }
    rules_json { Scoring::Rules.default.to_h }

    trait :draft do
      status { "draft" }
      published_at { nil }
    end
  end
end
