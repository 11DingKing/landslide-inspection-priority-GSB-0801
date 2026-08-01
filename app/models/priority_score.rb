# The materialised, explainable result of scoring one immutable snapshot with
# one policy version. All numbers are produced by Scoring::Engine and persisted
# here verbatim; this model performs no scoring. DB check constraints guarantee
# the component ranges and the exact sum == total invariant.
class PriorityScore < ApplicationRecord
  RISK_LEVELS = %w[low moderate high extreme].freeze
  SCHEDULING_STATUSES = %w[schedulable blocked].freeze

  belongs_to :evidence_snapshot
  belongs_to :scoring_policy
  belongs_to :hazard_point

  validates :rainfall_score, inclusion: { in: 0..40 }
  validates :history_score, inclusion: { in: 0..25 }
  validates :recency_score, inclusion: { in: 0..20 }
  validates :exposure_score, inclusion: { in: 0..15 }
  validates :total_score, inclusion: { in: 0..100 }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validates :scheduling_status, inclusion: { in: SCHEDULING_STATUSES }
  validate :components_sum_to_total

  # Stable queue ordering: highest priority first, ties broken by the immutable
  # hazard_point_id. Because the tiebreak key never changes, inserting new equal-
  # scored rows during continuous writes never reshuffles earlier pages.
  scope :queue_ordered, -> { order(total_score: :desc, hazard_point_id: :asc) }

  def blocked?
    scheduling_status == "blocked"
  end

  private

  def components_sum_to_total
    return if [rainfall_score, history_score, recency_score, exposure_score, total_score].any?(&:nil?)

    sum = rainfall_score + history_score + recency_score + exposure_score
    return if sum == total_score

    errors.add(:total_score, "must equal the sum of component scores (#{sum})")
  end
end
