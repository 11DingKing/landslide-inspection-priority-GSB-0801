module Scoring
  # Raised when publishing a policy whose effective_at instant is already
  # claimed by another published policy. Maps to HTTP 409 at the boundary.
  class OverlappingPolicyError < StandardError
    attr_reader :effective_at

    def initialize(effective_at)
      @effective_at = effective_at
      super("a published scoring policy already exists at effective_at=#{effective_at.inspect}")
    end
  end

  # Raised when no published policy is authoritative for a snapshot instant.
  class NoAuthoritativePolicyError < StandardError
    attr_reader :captured_at

    def initialize(captured_at)
      @captured_at = captured_at
      super("no published scoring policy is effective at or before #{captured_at.inspect}")
    end
  end
end
