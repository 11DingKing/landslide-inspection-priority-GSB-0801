module Scoring
  # Selects exactly one scoring strategy for a given point in time.
  #
  # Selection is FULLY DETERMINISTIC so that two callers racing at the same
  # effective moment always agree on the winner:
  #
  #   1. status = 'published'
  #   2. effective_at <= as_of
  #   3. order by effective_at DESC, published_at DESC NULLS LAST, id DESC
  #   4. pick the first row
  #
  # The database also enforces (via partial unique index) that at most one
  # published strategy exists per effective_at, eliminating ambiguous
  # overlaps at the source.
  class StrategySelector
    class NoStrategyError < StandardError; end

    def self.for_time(as_of = Time.current)
      new(as_of).select
    end

    def initialize(as_of)
      @as_of = as_of
    end

    def select
      strategy = ScoringStrategy
                 .published
                 .effective_on_or_before(@as_of)
                 .ordered_deterministically
                 .first

      unless strategy
        raise NoStrategyError,
              "no published scoring strategy effective at #{@as_of.iso8601}"
      end

      strategy
    end
  end
end
