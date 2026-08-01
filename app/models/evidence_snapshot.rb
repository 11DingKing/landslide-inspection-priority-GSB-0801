# frozen_string_literal: true

# Immutable by construction: the database trigger
# (see CreateEvidenceSnapshots) rejects every UPDATE/DELETE, and the model
# additionally refuses to persist changes to a persisted snapshot so callers
# get a validation error instead of a database exception.
class EvidenceSnapshot < ApplicationRecord
  belongs_to :hazard_point
  has_many :score_records, dependent: :restrict_with_error

  validates :rainfall_24h_mm, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than: 10_000 }
  validates :historical_event_count, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :captured_at, presence: true
  validates :road_accessible, inclusion: { in: [true, false] }
  validate :immutable_attributes_unchanged, on: :update

  def readonly?
    persisted?
  end

  def evidence
    {
      rainfall_24h_mm: rainfall_24h_mm,
      historical_event_count: historical_event_count,
      last_inspected_at: last_inspected_at,
      road_accessible: road_accessible,
      captured_at: captured_at
    }
  end

  private

  def immutable_attributes_unchanged
    errors.add(:base, "evidence snapshots are immutable") if changed.any?
  end
end
