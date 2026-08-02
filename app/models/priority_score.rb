class PriorityScore < ApplicationRecord
  RISK_LEVELS = %w[low medium high critical].freeze
  DISPATCH_STATUSES = %w[available blocked].freeze

  belongs_to :evidence_snapshot
  belongs_to :scoring_strategy
  belongs_to :hazard_point

  validates :total_score, presence: true,
                          numericality: { only_integer: true,
                                          greater_than_or_equal_to: 0,
                                          less_than_or_equal_to: 100 }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validates :dispatch_status, inclusion: { in: DISPATCH_STATUSES }
  validates :components, presence: true
  validates :snapshot_time, presence: true

  before_validation :copy_snapshot_time, on: :create

  scope :for_queue, lambda {
    includes(:hazard_point, :evidence_snapshot, :scoring_strategy)
      .order(Arel.sql("total_score DESC, hazard_point_id ASC"))
  }

  scope :blocked, -> { where(dispatch_status: "blocked") }
  scope :available, -> { where(dispatch_status: "available") }

  def component_by_name(name)
    components.find { |c| c["name"] == name }
  end

  def component_total_check
    components.sum { |c| c["score"].to_i }
  end

  private

  def copy_snapshot_time
    self.snapshot_time ||= evidence_snapshot&.snapshot_time
  end
end
