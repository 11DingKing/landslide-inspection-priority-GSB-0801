# frozen_string_literal: true

class ScoreRecord < ApplicationRecord
  belongs_to :hazard_point
  belongs_to :evidence_snapshot
  belongs_to :strategy_version

  validates :total_score, presence: true,
            numericality: { only_integer: true, in: Scoring::Engine::TOTAL_RANGE }
  validates :risk_level, inclusion: { in: Scoring::Engine::RISK_LEVELS }
  validates :scheduling_status, inclusion: { in: Scoring::Engine::SCHEDULING_STATUSES }
  validates :computed_at, presence: true
  validate :components_sum_must_equal_total

  scope :current, -> { where(is_current: true) }
  # Canonical queue order; ties broken by id so pagination is stable even
  # when many records share the same total score.
  scope :queue_order, -> { order(total_score: :desc, id: :asc) }

  # Explanation payload: component names, ranges and the locked snapshot time.
  def explanation
    {
      "score_record_id" => id,
      "hazard_point_id" => hazard_point_id,
      "evidence_snapshot_id" => evidence_snapshot_id,
      "snapshot_captured_at" => evidence_snapshot.captured_at.iso8601,
      "strategy_version" => strategy_version.version,
      "strategy_effective_from" => strategy_version.effective_from&.iso8601,
      "total_score" => total_score,
      "risk_level" => risk_level,
      "scheduling_status" => scheduling_status,
      "components" => Scoring::Engine::COMPONENTS.map do |name, max|
        {
          "name" => name,
          "score" => components.fetch(name),
          "range" => { "min" => 0, "max" => max }
        }
      end,
      "components_sum" => components.values.sum
    }
  end

  private

  def components_sum_must_equal_total
    return if components.nil? || total_score.nil?

    expected = Scoring::Engine::COMPONENTS.keys
    unless components.keys.sort == expected.sort
      errors.add(:components, "must contain exactly the locked components: #{expected.join(', ')}")
      return
    end
    unless components.values.sum == total_score
      errors.add(:total_score, "must equal the sum of component scores")
    end
  end
end
