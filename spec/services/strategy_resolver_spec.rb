require "rails_helper"

RSpec.describe StrategyResolver do
  describe ".resolve" do
    it "returns the latest published strategy effective at the given time" do
      older = create(:scoring_strategy, version: 1, effective_at: 3.days.ago)
      newer = create(:scoring_strategy, version: 2, effective_at: 1.day.ago)

      resolved = described_class.resolve(Time.current)
      expect(resolved.id).to eq(newer.id)

      resolved = described_class.resolve(2.days.ago)
      expect(resolved.id).to eq(older.id)
    end

    it "ignores draft strategies" do
      create(:scoring_strategy, :draft, version: 9, effective_at: 1.hour.ago)
      published = create(:scoring_strategy, version: 1, effective_at: 2.days.ago)

      expect(described_class.resolve(Time.current).id).to eq(published.id)
    end

    it "returns nil when no strategy is effective yet" do
      create(:scoring_strategy, effective_at: 2.days.from_now)
      expect(described_class.resolve(Time.current)).to be_nil
    end

    it "deterministically picks highest version among same effective_at if the DB allowed it" do
      time = 1.day.ago.beginning_of_day
      v1 = create(:scoring_strategy, version: 10, effective_at: time)
      v2 = create(:scoring_strategy, version: 11, effective_at: time + 1)

      expect(described_class.resolve(time + 2).id).to eq(v2.id)
      expect(described_class.resolve(time).id).to eq(v1.id)
    end
  end

  describe "overlap protection" do
    it "rejects two published strategies with identical effective_at" do
      time = 1.day.ago.beginning_of_day
      create(:scoring_strategy, effective_at: time)

      expect {
        StrategyManager.publish!(name: "dup", effective_at: time, rules: ScoringRules::V1.rules)
      }.to raise_error(StrategyManager::OverlappingStrategy)
    end
  end
end
