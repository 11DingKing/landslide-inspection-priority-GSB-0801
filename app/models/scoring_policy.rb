# A versioned, declarative scoring policy valid over a half-open interval
# [effective_from, effective_until). effective_until = nil means open-ended.
# ScoringPolicy carries no scoring logic itself — it only manages lifecycle
# (draft -> published -> archived), the validity interval, and the deterministic
# selection rule. Interpretation happens in Scoring::Engine.
class ScoringPolicy < ApplicationRecord
  STATUSES = %w[draft published archived].freeze

  has_many :priority_scores, dependent: :restrict_with_exception

  validates :version, presence: true, uniqueness: true
  validates :effective_from, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :interval_is_ordered

  scope :published, -> { where(status: "published") }

  # The authoritative policy for a given evidence instant: the published policy
  # whose validity interval contains captured_at, i.e.
  #   effective_from <= captured_at < effective_until (until NULL = open).
  # The DB exclusion constraint guarantees published intervals never overlap, so
  # at most one policy matches. id is a final deterministic tiebreak for safety.
  def self.authoritative_for(captured_at)
    published
      .where(effective_from: ..captured_at)
      .where("effective_until IS NULL OR effective_until > ?", captured_at)
      .order(effective_from: :desc, id: :desc)
      .first
  end

  def publish!(at: Time.current)
    raise ArgumentError, "effective_from is required to publish" if effective_from.nil?

    update!(status: "published", published_at: at)
  rescue ActiveRecord::StatementInvalid => e
    raise unless overlap_violation?(e)

    raise Scoring::OverlappingPolicyError.new(effective_from, effective_until)
  end

  # Close an already-published policy's interval at `boundary` WITHOUT retiring
  # it. The policy stays published and thus still scores/reproduces any snapshot
  # captured before the boundary — this is what keeps historical replay intact
  # while a successor takes over from the boundary onward.
  def bound!(boundary)
    unless published?
      raise ArgumentError, "only a published policy can be bounded"
    end

    update!(effective_until: boundary)
  rescue ActiveRecord::StatementInvalid => e
    raise unless overlap_violation?(e)

    raise Scoring::OverlappingPolicyError.new(effective_from, boundary)
  end

  def published?
    status == "published"
  end

  private

  def interval_is_ordered
    return if effective_until.nil? || effective_from.nil?
    return if effective_until > effective_from

    errors.add(:effective_until, "must be after effective_from")
  end

  def overlap_violation?(error)
    error.cause.is_a?(PG::ExclusionViolation)
  end
end
