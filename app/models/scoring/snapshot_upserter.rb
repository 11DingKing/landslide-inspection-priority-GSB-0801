module Scoring
  # Idempotently creates an EvidenceSnapshot keyed by business_key.
  #
  # Behaviour:
  #   * no business_key provided -> normal create (always inserts)
  #   * same business_key + same payload -> returns existing row
  #     (created? = false, status = :ok)
  #   * same business_key + different payload -> raises
  #     PayloadConflict (409)
  #   * two concurrent callers race -> unique index guarantees only one
  #     row; the loser re-reads it and follows the same payload rules.
  class SnapshotUpserter
    class PayloadConflict < StandardError
      attr_reader :existing
      def initialize(existing)
        @existing = existing
        super("evidence_snapshot with business_key=#{existing.business_key} " \
              "already exists with a different payload")
      end
    end

    Result = Struct.new(:snapshot, :created?, keyword_init: true)

    def self.call(hazard_point, attrs)
      new(hazard_point, attrs).call
    end

    def initialize(hazard_point, attrs)
      @hazard_point = hazard_point
      @attrs = attrs.to_h.symbolize_keys
      @business_key = @attrs[:business_key]
    end

    def call
      return create_direct unless @business_key.present?

      existing = EvidenceSnapshot.find_by(business_key: @business_key)
      if existing
        ensure_same_payload!(existing, candidate_for_comparison)
        return Result.new(snapshot: existing, created?: false)
      end

      snapshot = create_with_race_retry
      Result.new(snapshot: snapshot, created?: snapshot.previously_new_record?)
    end

    private

    def create_direct
      snapshot = @hazard_point.evidence_snapshots.create!(@attrs)
      Result.new(snapshot: snapshot, created?: true)
    end

    # First INSERT wins. If a concurrent caller inserted the same business_key
    # first, we catch either the model-level uniqueness validation or the
    # database unique violation, then reload the existing row and apply the
    # same payload comparison. Wrapped in a savepoint so a constraint failure
    # does not abort the outer transaction.
    def create_with_race_retry
      EvidenceSnapshot.transaction(requires_new: true) do
        @hazard_point.evidence_snapshots.create!(@attrs)
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      is_business_key_error =
        e.is_a?(ActiveRecord::RecordNotUnique) ||
        e.record&.errors&.key?(:business_key)
      raise unless is_business_key_error

      existing = EvidenceSnapshot.find_by!(business_key: @business_key)
      ensure_same_payload!(existing, candidate_for_comparison)
      existing
    end

    def candidate_for_comparison
      EvidenceSnapshot.new(@attrs.slice(*EvidenceSnapshot::PAYLOAD_FIELDS.map(&:to_sym)))
    end

    def ensure_same_payload!(existing, candidate)
      return if existing.same_payload_as?(candidate)

      raise PayloadConflict, existing
    end
  end
end
