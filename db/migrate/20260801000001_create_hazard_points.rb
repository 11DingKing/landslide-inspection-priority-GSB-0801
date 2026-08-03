# frozen_string_literal: true

class CreateHazardPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :hazard_points do |t|
      t.string :external_code, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.timestamps
    end
    add_index :hazard_points, :external_code, unique: true
  end
end
