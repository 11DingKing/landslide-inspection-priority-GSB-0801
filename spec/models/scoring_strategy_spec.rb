require "rails_helper"

RSpec.describe ScoringStrategy, type: :model do
  describe "published immutability" do
    it "prevents mutating rules/version/effective_at once published" do
      strategy = create(:scoring_strategy)
      expect(strategy).to be_published

      expect {
        strategy.update!(name: "changed")
      }.not_to raise_error

      expect {
        strategy.update!(rules: ScoringRules::V1.rules.merge("x" => 1))
      }.to raise_error(ActiveRecord::RecordInvalid, /immutable/)
    end
  end

  describe "version auto-assignment" do
    it "assigns the next version number" do
      s1 = StrategyManager.publish!(name: "a", effective_at: 2.days.ago, rules: ScoringRules::V1.rules)
      s2 = StrategyManager.draft(name: "b", effective_at: 1.day.ago, rules: ScoringRules::V1.rules)
      expect(s1.version).to eq(1)
      expect(s2.version).to eq(2)
    end
  end
end

RSpec.describe "concurrent strategy publication", :concurrency do
  self.use_transactional_tests = false

  it "rejects the second transaction when two candidates publish at the same effective_at" do
    time = 1.day.ago.beginning_of_day
    errors = []
    wins = Concurrent::AtomicFixnum.new(0)

    threads = 2.times.map do |i|
      Thread.new do
        begin
          StrategyManager.publish!(
            name: "candidate-#{i}",
            version: i + 1,
            effective_at: time,
            rules: ScoringRules::V1.rules
          )
          wins.increment
        rescue StrategyManager::OverlappingStrategy => e
          errors << e
        rescue ActiveRecord::RecordNotUnique
          errors << :unique
        end
      end
    end
    threads.each(&:join)

    expect(wins.value).to eq(1)
    expect(errors.length).to eq(1)
    expect(ScoringStrategy.published.where(effective_at: time).count).to eq(1)
  end
end
