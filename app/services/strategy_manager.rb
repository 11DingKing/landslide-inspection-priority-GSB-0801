class StrategyManager
  class Error < StandardError; end
  class OverlappingStrategy < Error; end

  def self.draft(attributes)
    ScoringStrategy.create!(attributes.merge(status: "draft"))
  end

  def self.publish!(attributes)
    strategy = ScoringStrategy.new(attributes.merge(status: "published"))
    strategy.save!
    strategy
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("index_scoring_strategies_on_published_effective_at")
      raise OverlappingStrategy,
            "a published strategy already exists with effective_at #{attributes[:effective_at]}"
    end
    raise
  end

  def self.publish_draft!(strategy)
    strategy.update!(status: "published")
    strategy
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("index_scoring_strategies_on_published_effective_at")
      raise OverlappingStrategy,
            "a published strategy already exists with effective_at #{strategy.effective_at}"
    end
    raise
  end
end
