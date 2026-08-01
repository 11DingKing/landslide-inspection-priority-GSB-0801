# frozen_string_literal: true

class HazardPoint < ApplicationRecord
  has_many :evidence_snapshots, dependent: :restrict_with_error
  has_many :score_records, dependent: :restrict_with_error

  validates :external_code, presence: true, uniqueness: true
  validates :name, :kind, presence: true
end
