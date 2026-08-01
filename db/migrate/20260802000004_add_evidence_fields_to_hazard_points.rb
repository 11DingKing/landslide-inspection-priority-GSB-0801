class AddEvidenceFieldsToHazardPoints < ActiveRecord::Migration[8.1]
  def change
    add_column :hazard_points, :historical_event_count, :integer, null: false, default: 0
    add_column :hazard_points, :latest_rainfall_24h_mm, :decimal, precision: 8, scale: 1, default: 0

    add_index :hazard_points, :historical_event_count
  end
end
