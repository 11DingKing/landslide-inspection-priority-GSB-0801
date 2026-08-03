# frozen_string_literal: true

class StrategyVersion < ApplicationRecord
  STATUSES = %w[draft published retired].freeze

  has_many :score_records, dependent: :restrict_with_error

  validates :version, presence: true, uniqueness: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :rules, presence: true
  validates :effective_range, presence: true
  validate :rules_must_match_locked_schema

  scope :published, -> { where(status: "published") }

  # The unique published version covering +at+. Uniqueness is guaranteed by
  # the exclusion constraint strategy_versions_no_published_overlap, so this
  # can never be ambiguous.
  scope :effective_at, ->(at) { published.where("effective_range @> ?::timestamptz", at) }

  def self.applicable_to(at)
    effective_at(at).first
  end

  # Builds the canonical half-open tstzrange literal for a new version.
  def self.compose_range(from, to)
    raise ArgumentError, "effective_from is required" if from.nil?

    "[#{from.to_time.utc.iso8601(6)},#{to ? to.to_time.utc.iso8601(6) : 'infinity'})"
  end

  # Publishes the draft for its effective range. If another published version
  # overlaps, PostgreSQL raises an exclusion-constraint violation which the
  # caller translates into a conflict; exactly one candidate wins.
  def publish!
    update!(status: "published", published_at: Time.current)
  end

  def retire!
    update!(status: "retired")
  end

  def effective_from
    parsed_range&.begin
  end

  def effective_to
    parsed_range&.end
  end

  private

  def parsed_range
    raw = self[:effective_range]
    return if raw.nil?
    return raw if raw.is_a?(Range)

    match = /\A[\[\(](?<from>[^,]*),(?<to>[^\]\)]*)[\]\)]\z/.match(raw.to_s)
    from = match[:from].presence && match[:from] != "-infinity" ? Time.zone.parse(match[:from].delete('"')) : nil
    to = match[:to].presence && match[:to] != "infinity" ? Time.zone.parse(match[:to].delete('"')) : nil
    from...to
  end

  def rules_must_match_locked_schema
    Scoring::Engine.validate_rules!(rules)
  rescue Scoring::Engine::InvalidRules => e
    errors.add(:rules, e.message)
  end
end
