class ScoringStrategy < ApplicationRecord
  STATUSES = %w[draft published].freeze
  POINT_TYPES = %w[cut_slope_building road_slope registered_hazard].freeze

  validates :version, presence: true, uniqueness: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true
  validates :effective_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :rules, presence: true
  validate :validate_rules_structure

  before_validation :assign_next_version, on: :create
  validate :published_strategy_is_immutable, on: :update

  scope :published, -> { where(status: "published") }
  scope :effective_at_or_before, ->(time) { where("effective_at <= ?", time) }

  def published?
    status == "published"
  end

  def items
    rules.fetch("items", [])
  end

  def risk_levels
    rules.fetch("risk_levels", [])
  end

  private

  def assign_next_version
    return if version.present?

    max_version = self.class.maximum(:version) || 0
    self.version = max_version + 1
  end

  def published_strategy_is_immutable
    return unless status_was == "published"

    if rules_changed? || version_changed? || effective_at_changed?
      errors.add(:base, "a published strategy is immutable")
    end
  end

  def validate_rules_structure
    return if rules.blank?

    unless rules.is_a?(Hash) && rules["items"].is_a?(Array) && rules["items"].any?
      errors.add(:rules, "must contain an 'items' array")
      return
    end

    unless rules["risk_levels"].is_a?(Array) && rules["risk_levels"].any?
      errors.add(:rules, "must contain a 'risk_levels' array")
      return
    end

    rules["items"].each do |item|
      valid_basics = item["key"].present? && item["name"].present? &&
                     item["max"].is_a?(Numeric) && item["type"].present?
      valid_details =
        case item["type"]
        when "numeric_tier"
          item["tiers"].is_a?(Array) && item["tiers"].any?
        when "categorical", "inspection_recency"
          item["values"].is_a?(Hash) && item["values"].any?
        else
          false
        end

      unless valid_basics && valid_details
        errors.add(:rules, "item #{item['key'].inspect} is invalid")
      end
    end

    seen_keys = rules["items"].map { |i| i["key"] }
    if seen_keys.uniq.length != seen_keys.length
      errors.add(:rules, "item keys must be unique")
    end
  end
end
