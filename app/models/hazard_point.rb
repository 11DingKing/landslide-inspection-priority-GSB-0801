class HazardPoint < ApplicationRecord
  POINT_TYPES = %w[cut_slope_building road_slope registered_hazard].freeze
  ROAD_STATUSES = %w[accessible closed].freeze

  validates :name, presence: true
  validates :point_type, presence: true, inclusion: { in: POINT_TYPES }
  validates :road_accessible, inclusion: { in: [true, false] }
  validates :historical_event_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :latest_rainfall_24h_mm, numericality: { greater_than_or_equal_to: 0 }

  has_many :evidence_snapshots, dependent: :restrict_with_error

  before_save :sync_road_closed_at

  def road_status
    road_accessible? ? "accessible" : "closed"
  end

  def latest_snapshot
    evidence_snapshots.order(snapshot_at: :desc, id: :desc).first
  end

  private

  def sync_road_closed_at
    if road_accessible
      self.road_closed_at = nil
    elsif road_closed_at.nil?
      self.road_closed_at = Time.current
    end
  end
end
