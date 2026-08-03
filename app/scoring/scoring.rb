module Scoring
  # Raised when publishing a policy whose validity interval would overlap an
  # already-published policy. Maps to HTTP 409 at the boundary.
  class OverlappingPolicyError < StandardError
    attr_reader :effective_from, :effective_until

    def initialize(effective_from, effective_until = nil)
      @effective_from = effective_from
      @effective_until = effective_until
      super("a published scoring policy already overlaps " \
            "[#{effective_from.inspect}, #{effective_until.inspect})")
    end
  end

  # Raised when no published policy is authoritative for a snapshot instant.
  class NoAuthoritativePolicyError < StandardError
    attr_reader :captured_at

    def initialize(captured_at)
      @captured_at = captured_at
      super("no published scoring policy is effective at #{captured_at.inspect}")
    end
  end

  # Raised when the same snapshot business_key is re-submitted with a different
  # payload. Same key must always mean the same evidence. Maps to HTTP 409.
  class ConflictingBusinessKeyError < StandardError
    attr_reader :business_key

    def initialize(business_key)
      @business_key = business_key
      super("evidence business_key #{business_key.inspect} already exists with a different payload")
    end
  end
end
