class StrategySerializer
  def self.one(strategy)
    {
      id: strategy.id,
      version: strategy.version,
      name: strategy.name,
      description: strategy.description,
      effective_at: strategy.effective_at.iso8601,
      status: strategy.status,
      rules: strategy.rules,
      created_at: strategy.created_at.iso8601,
      updated_at: strategy.updated_at.iso8601
    }
  end

  def self.many(strategies)
    strategies.map { |s| one(s) }
  end
end
