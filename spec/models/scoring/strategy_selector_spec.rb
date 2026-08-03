require "rails_helper"

RSpec.describe Scoring::StrategySelector do
  let!(:old) do
    create(:scoring_strategy, version_code: "v1-old",
                              effective_at: 60.days.ago, published_at: 60.days.ago)
  end
  let!(:recent) do
    create(:scoring_strategy, version_code: "v2-new",
                              effective_at: 10.days.ago, published_at: 10.days.ago)
  end

  it "picks the most recent published strategy effective at the given time" do
    expect(described_class.for_time(Time.current).id).to eq(recent.id)
    expect(described_class.for_time(20.days.ago).id).to eq(old.id)
  end

  it "ignores draft strategies" do
    create(:scoring_strategy, :draft, version_code: "draft-v",
                                      effective_at: 1.minute.ago)
    expect(described_class.for_time(Time.current).id).to eq(recent.id)
  end

  it "raises NoStrategyError when no published strategy exists" do
    ScoringStrategy.delete_all
    expect { described_class.for_time(Time.current) }
      .to raise_error(Scoring::StrategySelector::NoStrategyError)
  end

  it "rejects two published strategies at the same effective_at via DB constraint" do
    same_time = 5.days.ago.beginning_of_day
    create(:scoring_strategy, version_code: "dup-a",
                              effective_at: same_time, published_at: Time.current)
    expect {
      create(:scoring_strategy, version_code: "dup-b",
                                effective_at: same_time, published_at: Time.current)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows two drafts at the same effective_at but only one can publish" do
    same_time = 3.days.ago.beginning_of_day
    d1 = create(:scoring_strategy, :draft, version_code: "draft-a",
                                           effective_at: same_time)
    d2 = create(:scoring_strategy, :draft, version_code: "draft-b",
                                           effective_at: same_time)
    d1.publish!
    expect { d2.publish! }.to raise_error(ScoringStrategy::StrategyOverlapError)
  end

  it "is deterministic when many strategies have close effective times" do
    times = [5.days.ago, 5.days.ago + 1.second, 5.days.ago + 2.seconds]
    times.each_with_index do |t, i|
      create(:scoring_strategy, version_code: "det-#{i}",
                                effective_at: t, published_at: Time.current)
    end
    chosen = described_class.for_time(Time.current)
    3.times do
      expect(described_class.for_time(Time.current).id).to eq(chosen.id)
    end
  end
end
