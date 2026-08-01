class CreateHazardPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :hazard_points do |t|
      t.string :name, null: false
      t.string :point_type, null: false
      t.string :location
      t.boolean :road_accessible, null: false, default: true
      t.datetime :road_closed_at
      t.datetime :last_inspected_at

      t.timestamps
    end

    add_index :hazard_points, :point_type
    add_index :hazard_points, :road_accessible
    add_index :hazard_points, :last_inspected_at
  end
end
