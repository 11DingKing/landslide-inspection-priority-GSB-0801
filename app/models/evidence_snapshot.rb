class EvidenceSnapshot < ApplicationRecord
  RISK_LEVELS = %w[low medium high critical].freeze
  DISPATCH_STATUSES = %w[schedulable blocked].freeze
  ROAD_STATUSES = %w[accessible closed].freeze

  belongs_to :hazard_point
  belongs_to :scoring_strategy

  validates :snapshot_at, presence: true
  validates :rainfall_24h_mm, presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validates :historical_event_count, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :point_type, presence: true, inclusion: { in: HazardPoint::POINT_TYPES }
  validates :road_status, presence: true, inclusion: { in: ROAD_STATUSES }
  validates :total_score, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :risk_level, presence: true, inclusion: { in: RISK_LEVELS }
  validates :dispatch_status, presence: true, inclusion: { in: DISPATCH_STATUSES }
  validates :score_breakdown, presence: true
  validate :breakdown_is_well_formed
  validate :breakdown_sum_equals_total

  after_initialize :mark_readonly_if_persisted, if: :persisted?

  def road_blocked?
    road_status == "closed"
  end

  def strategy_version
    scoring_strategy.version
  end

  def explanation_text
    explanation.is_a?(Hash) ? explanation["summary"] : explanation
  end

  private

  def mark_readonly_if_persisted
    readonly!
  end

  def breakdown_is_well_formed
    return if score_breakdown.blank?

    unless score_breakdown.is_a?(Array)
      errors.add(:score_breakdown, "must be an array")
      return
    end

    score_breakdown.each do |item|
      unless item["key"].present? && item["name"].present? &&
             item["score"].is_a?(Numeric) && item["max"].is_a?(Numeric)
        errors.add(:score_breakdown, "each item needs key, name, score and max")
      end
    end
  end

  def breakdown_sum_equals_total
    return if score_breakdown.blank? || total_score.blank?
    return unless score_breakdown.is_a?(Array)

    sum = score_breakdown.sum { |i| i["score"].to_i }
    unless sum == total_score.to_i
      errors.add(:total_score,
                 "must equal the sum of score_breakdown (#{sum})")
    end
  end
end
