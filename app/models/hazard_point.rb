class HazardPoint < ApplicationRecord
  KINDS = %w[cut_slope_building road_slope registered_hazard].freeze

  has_many :evidence_snapshots, dependent: :restrict_with_error
  has_many :priority_scores, dependent: :destroy

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :name, presence: true

  scope :ordered, -> { order(:id) }
end
