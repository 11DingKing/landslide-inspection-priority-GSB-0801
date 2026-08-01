class CreateHazardPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :hazard_points do |t|
      t.string :code, null: false
      t.string :name, null: false
      # Locked category vocabulary. Drives the exposure component and is
      # interpreted only by the scoring engine, never by callbacks.
      t.string :category, null: false
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      # Most recent inspection known for the point. Snapshots freeze their own
      # copy at capture time so replays never read a drifting value.
      t.datetime :last_inspected_at

      t.timestamps
    end

    add_index :hazard_points, :code, unique: true
    add_index :hazard_points, :category
  end
end
