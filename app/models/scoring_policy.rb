# A versioned, declarative scoring policy. The `definition` jsonb holds all
# weights/thresholds; ScoringPolicy carries no scoring logic itself — it only
# manages lifecycle (draft -> published -> archived) and the deterministic
# selection rule. Interpretation happens in Scoring::Engine.
class ScoringPolicy < ApplicationRecord
  STATUSES = %w[draft published archived].freeze

  has_many :priority_scores, dependent: :restrict_with_exception

  validates :version, presence: true, uniqueness: true
  validates :effective_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }

  # The authoritative policy for a given evidence instant: the published policy
  # with the greatest effective_at not after `captured_at`. Ties on effective_at
  # cannot occur among published policies (DB partial-unique index), so the
  # winner is always unique. id is a final deterministic tiebreak for safety.
  def self.authoritative_for(captured_at)
    published
      .where(effective_at: ..captured_at)
      .order(effective_at: :desc, id: :desc)
      .first
  end

  def publish!(at: Time.current)
    raise ArgumentError, "effective_at is required to publish" if effective_at.nil?

    update!(status: "published", published_at: at)
  rescue ActiveRecord::RecordNotUnique
    # Another candidate already holds this exact effective_at instant. The DB
    # partial-unique index rejects the overlap; surface it as a domain conflict.
    raise Scoring::OverlappingPolicyError.new(effective_at)
  end

  def published?
    status == "published"
  end
end
