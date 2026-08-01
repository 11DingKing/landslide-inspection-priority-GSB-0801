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

ActiveRecord::Schema[8.1].define(version: 2026_08_01_000004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "evidence_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.bigint "hazard_point_id", null: false
    t.integer "historical_event_count", default: 0, null: false
    t.datetime "point_last_inspected_at"
    t.decimal "rainfall_mm_24h", precision: 8, scale: 2, default: "0.0", null: false
    t.boolean "road_accessible", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["content_digest"], name: "index_evidence_snapshots_on_content_digest"
    t.index ["hazard_point_id", "captured_at"], name: "index_evidence_snapshots_on_hazard_point_id_and_captured_at"
    t.index ["hazard_point_id"], name: "index_evidence_snapshots_on_hazard_point_id"
  end

  create_table "hazard_points", force: :cascade do |t|
    t.string "category", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "last_inspected_at"
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_hazard_points_on_category"
    t.index ["code"], name: "index_hazard_points_on_code", unique: true
  end

  create_table "priority_scores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "evidence_captured_at", null: false
    t.bigint "evidence_snapshot_id", null: false
    t.integer "exposure_score", null: false
    t.bigint "hazard_point_id", null: false
    t.integer "history_score", null: false
    t.string "policy_version", null: false
    t.integer "rainfall_score", null: false
    t.integer "recency_score", null: false
    t.string "risk_level", null: false
    t.string "scheduling_status", default: "schedulable", null: false
    t.bigint "scoring_policy_id", null: false
    t.integer "total_score", null: false
    t.datetime "updated_at", null: false
    t.index ["evidence_snapshot_id", "scoring_policy_id"], name: "index_priority_scores_on_snapshot_and_policy", unique: true
    t.index ["evidence_snapshot_id"], name: "index_priority_scores_on_evidence_snapshot_id"
    t.index ["hazard_point_id"], name: "index_priority_scores_on_hazard_point_id"
    t.index ["scoring_policy_id"], name: "index_priority_scores_on_scoring_policy_id"
    t.index ["total_score", "id"], name: "index_priority_scores_on_total_and_id", order: { total_score: :desc }
    t.check_constraint "exposure_score >= 0 AND exposure_score <= 15", name: "priority_scores_exposure_range"
    t.check_constraint "history_score >= 0 AND history_score <= 25", name: "priority_scores_history_range"
    t.check_constraint "rainfall_score >= 0 AND rainfall_score <= 40", name: "priority_scores_rainfall_range"
    t.check_constraint "recency_score >= 0 AND recency_score <= 20", name: "priority_scores_recency_range"
    t.check_constraint "scheduling_status::text = ANY (ARRAY['schedulable'::character varying, 'blocked'::character varying]::text[])", name: "priority_scores_scheduling_status_check"
    t.check_constraint "total_score = (rainfall_score + history_score + recency_score + exposure_score)", name: "priority_scores_components_sum_to_total"
    t.check_constraint "total_score >= 0 AND total_score <= 100", name: "priority_scores_total_range"
  end

  create_table "scoring_policies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "definition", default: {}, null: false
    t.datetime "effective_at", null: false
    t.datetime "published_at"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["effective_at"], name: "index_published_policies_on_effective_at", unique: true, where: "((status)::text = 'published'::text)"
    t.index ["status"], name: "index_scoring_policies_on_status"
    t.index ["version"], name: "index_scoring_policies_on_version", unique: true
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'archived'::character varying]::text[])", name: "scoring_policies_status_check"
  end

  add_foreign_key "evidence_snapshots", "hazard_points"
  add_foreign_key "priority_scores", "evidence_snapshots"
  add_foreign_key "priority_scores", "hazard_points"
  add_foreign_key "priority_scores", "scoring_policies"
end
