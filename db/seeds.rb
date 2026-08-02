# Idempotent seed data.
#
# Creates one baseline published scoring strategy and the three mandatory
# hazard points described in the spec, each with a different last-inspection
# combination (never, earlier, same-day) and the required rainfall / history /
# road-accessibility inputs.

now = Time.current

# --- Strategy ---------------------------------------------------------------

baseline = ScoringStrategy.find_or_initialize_by(version_code: "v1.0-baseline")
baseline.assign_attributes(
  name: "Baseline post-rainfall priority v1.0",
  effective_at: 1.month.ago.beginning_of_day,
  rules_json: Scoring::Rules.default.to_h,
  change_note: "Initial baseline shipped with the service."
)
baseline.publish!(now) unless baseline.published?
baseline.save!

# --- Hazard points ----------------------------------------------------------

points_data = [
  {
    name: "切坡建房点 A",
    kind: "cut_slope_building",
    external_code: "HP-CS-001",
    road_accessible: true,
    rainfall: 186.0,
    history: 2,
    last_inspected_at: nil,
    note: "从未巡查（last_inspected_at = NULL）"
  },
  {
    name: "道路边坡点 B",
    kind: "road_slope",
    external_code: "HP-RD-001",
    road_accessible: false,
    rainfall: 112.0,
    history: 0,
    last_inspected_at: 70.hours.ago,
    note: "较早巡查（70 小时前），道路封闭"
  },
  {
    name: "登记隐患点 C",
    kind: "registered_hazard",
    external_code: "HP-RG-001",
    road_accessible: true,
    rainfall: 95.0,
    history: 1,
    last_inspected_at: 6.hours.ago,
    note: "当日已巡查（6 小时前）"
  }
]

points_data.each do |data|
  point = HazardPoint.find_or_initialize_by(external_code: data[:external_code])
  point.assign_attributes(
    name: data[:name],
    kind: data[:kind],
    road_accessible: data[:road_accessible],
    description: data[:note]
  )
  point.save!

  snap = point.evidence_snapshots.find_or_initialize_by(snapshot_time: now)
  snap.assign_attributes(
    rainfall_24h_mm: data[:rainfall],
    historical_event_count: data[:history],
    last_inspected_at: data[:last_inspected_at],
    road_accessible: data[:road_accessible],
    source_note: data[:note],
    raw_payload: {
      rainfall_24h_mm: data[:rainfall],
      historical_event_count: data[:history],
      seed: true
    }
  )
  snap.save!
  snap.lock!

  Scoring::PriorityComputer.call(snap, now: now)
end

puts "Seeded baseline strategy and #{points_data.size} hazard points."
