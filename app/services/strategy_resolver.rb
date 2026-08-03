class StrategyResolver
  class Error < StandardError; end
  class NoActiveStrategy < Error; end

  def self.resolve(time = Time.current)
    ScoringStrategy
      .published
      .effective_at_or_before(time)
      .order(effective_at: :desc, version: :desc)
      .first
  end

  def self.resolve!(time = Time.current)
    resolve(time) || raise(NoActiveStrategy, "no published strategy effective at #{time.iso8601}")
  end

  def self.find_version(version)
    ScoringStrategy.published.find_by!(version: version)
  end
end
