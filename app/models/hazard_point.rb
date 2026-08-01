class HazardPoint < ApplicationRecord
  # Locked category vocabulary. Interpreted only by Scoring::Engine.
  CATEGORIES = %w[cut_slope_housing road_slope registered_hazard].freeze

  has_many :evidence_snapshots, dependent: :destroy
  has_many :priority_scores, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
end
