# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_02_231236) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "dispatch_status", ["available", "blocked"]
  create_enum "hazard_point_kind", ["cut_slope_building", "road_slope", "registered_hazard"]
  create_enum "risk_level", ["low", "medium", "high", "critical"]
  create_enum "strategy_status", ["draft", "published", "retired"]

  create_table "evidence_snapshots", force: :cascade do |t|
    t.string "business_key"
    t.datetime "created_at", null: false
    t.bigint "hazard_point_id", null: false
    t.integer "historical_event_count", default: 0, null: false
    t.boolean "immutable", default: false, null: false
    t.datetime "last_inspected_at", precision: nil
    t.decimal "rainfall_24h_mm", precision: 7, scale: 2, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.boolean "road_accessible", default: true, null: false
    t.datetime "snapshot_time", precision: nil, null: false
    t.text "source_note"
    t.datetime "updated_at", null: false
    t.index ["business_key"], name: "index_evidence_snapshots_on_business_key", unique: true
    t.index ["hazard_point_id", "snapshot_time"], name: "idx_evidence_snapshots_point_time"
    t.index ["hazard_point_id"], name: "index_evidence_snapshots_on_hazard_point_id"
    t.index ["snapshot_time"], name: "index_evidence_snapshots_on_snapshot_time"
  end

  create_table "hazard_points", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_code"
    t.enum "kind", null: false, enum_type: "hazard_point_kind"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "name", null: false
    t.boolean "road_accessible", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["external_code"], name: "index_hazard_points_on_external_code", unique: true
    t.index ["kind"], name: "index_hazard_points_on_kind"
  end

  create_table "priority_scores", force: :cascade do |t|
    t.jsonb "components", default: [], null: false
    t.datetime "created_at", null: false
    t.enum "dispatch_status", default: "available", null: false, enum_type: "dispatch_status"
    t.bigint "evidence_snapshot_id", null: false
    t.jsonb "explanation", default: {}, null: false
    t.bigint "hazard_point_id", null: false
    t.string "kind", default: "current", null: false
    t.enum "risk_level", null: false, enum_type: "risk_level"
    t.boolean "road_accessible", default: true, null: false
    t.bigint "scoring_strategy_id", null: false
    t.datetime "snapshot_time", precision: nil, null: false
    t.integer "total_score", null: false
    t.datetime "updated_at", null: false
    t.index ["dispatch_status"], name: "index_priority_scores_on_dispatch_status"
    t.index ["evidence_snapshot_id", "scoring_strategy_id"], name: "idx_priority_scores_snapshot_strategy", unique: true
    t.index ["evidence_snapshot_id"], name: "idx_priority_scores_one_current_per_snapshot", unique: true, where: "((kind)::text = 'current'::text)"
    t.index ["evidence_snapshot_id"], name: "index_priority_scores_on_evidence_snapshot_id"
    t.index ["hazard_point_id"], name: "index_priority_scores_on_hazard_point_id"
    t.index ["kind"], name: "index_priority_scores_on_kind"
    t.index ["risk_level"], name: "index_priority_scores_on_risk_level"
    t.index ["scoring_strategy_id"], name: "index_priority_scores_on_scoring_strategy_id"
    t.index ["total_score", "hazard_point_id"], name: "idx_priority_scores_queue_order"
  end

  create_table "scoring_strategies", force: :cascade do |t|
    t.text "change_note"
    t.datetime "created_at", null: false
    t.datetime "effective_at", precision: nil, null: false
    t.string "name", null: false
    t.datetime "published_at", precision: nil
    t.jsonb "rules_json", default: {}, null: false
    t.enum "status", default: "draft", null: false, enum_type: "strategy_status"
    t.datetime "updated_at", null: false
    t.string "version_code", null: false
    t.index ["effective_at"], name: "idx_strategies_effective_at"
    t.index ["effective_at"], name: "idx_strategies_one_published_per_effective_at", unique: true, where: "(status = 'published'::strategy_status)"
    t.index ["version_code"], name: "index_scoring_strategies_on_version_code", unique: true
  end

  add_foreign_key "evidence_snapshots", "hazard_points", on_delete: :restrict
  add_foreign_key "priority_scores", "evidence_snapshots", on_delete: :restrict
  add_foreign_key "priority_scores", "hazard_points", on_delete: :cascade
  add_foreign_key "priority_scores", "scoring_strategies", on_delete: :restrict
end
