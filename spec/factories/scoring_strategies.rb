FactoryBot.define do
  factory :scoring_strategy do
    sequence(:version) { |n| n }
    name { "策略 v#{version}" }
    effective_at { 1.day.ago }
    status { "published" }
    rules { ScoringRules::V1.rules }

    trait :draft do
      status { "draft" }
    end
  end
end
