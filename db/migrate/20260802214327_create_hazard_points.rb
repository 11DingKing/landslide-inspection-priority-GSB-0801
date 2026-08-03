class CreateHazardPoints < ActiveRecord::Migration[8.1]
  def change
    create_enum :hazard_point_kind, %w[cut_slope_building road_slope registered_hazard]

    create_table :hazard_points do |t|
      t.enum :kind, enum_type: :hazard_point_kind, null: false
      t.string :name, null: false
      t.text :description
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.string :external_code
      t.boolean :road_accessible, null: false, default: true
      t.timestamps
    end

    add_index :hazard_points, :external_code, unique: true
    add_index :hazard_points, :kind
  end
end
