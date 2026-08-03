class QueueRead < ApplicationRecord
  DISPATCH_STATUSES = %w[schedulable blocked].freeze

  validates :business_id, presence: true, uniqueness: true
  validates :strategy_version, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :cutoff_at, presence: true
  validates :dispatch_status, inclusion: { in: DISPATCH_STATUSES }, allow_nil: true

  after_initialize :mark_readonly_if_persisted, if: :persisted?

  def includes_blocked?
    dispatch_status.nil?
  end

  private

  def mark_readonly_if_persisted
    readonly!
  end
end
