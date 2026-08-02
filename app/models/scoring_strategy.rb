class ScoringStrategy < ApplicationRecord
  STATUSES = %w[draft published retired].freeze

  validates :name, presence: true
  validates :version_code, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :effective_at, presence: true
  validate :rules_json_is_hash
  validate :published_has_published_at

  scope :published, -> { where(status: "published") }
  scope :effective_on_or_before, ->(time) { where("effective_at <= ?", time) }
  scope :ordered_deterministically, lambda {
    order(Arel.sql("effective_at DESC, published_at DESC NULLS LAST, id DESC"))
  }

  def publish!(at = Time.current)
    raise "already published" if published?

    self.class.transaction do
      self.status = "published"
      self.published_at = at
      save!
    end
    self
  rescue ActiveRecord::RecordNotUnique => e
    raise StrategyOverlapError,
          "another published strategy is already effective at #{effective_at.iso8601}: #{e.message}"
  end

  def published?
    status == "published"
  end

  def rules
    @rules ||= Scoring::Rules.from_hash(rules_json)
  end

  private

  def rules_json_is_hash
    return if rules_json.is_a?(Hash)

    errors.add(:rules_json, "must be a JSON object")
  end

  def published_has_published_at
    return unless published? && published_at.nil?

    errors.add(:published_at, "must be set when status is published")
  end

  class StrategyOverlapError < StandardError; end
end
