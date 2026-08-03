# Idempotent seed data.
#
# Creates two published scoring strategies:
#   * v1.0-baseline  effective 2026-01-01T00:00:00Z
#   * v2.0-refined   effective 2026-08-02T00:00:00Z (boundary; NOT retiring v1)
#
# Three hazard points are created; their "old" snapshots (taken before the
# boundary) remain bound to v1 because the strategy selector picks the
# newest strategy whose effective_at <= snapshot_time. An additional snapshot
# for RDS-002 at the boundary moment is bound to v2.
#
# v1 is deliberately NOT retired so that every historical snapshot can still
# be replayed against its original rule version.

BOUNDARY = Time.utc(2026, 8, 2, 0, 0, 0).freeze
V1_EFFECTIVE = Time.utc(2026, 1, 1, 0, 0, 0).freeze
V2_EFFECTIVE = BOUNDARY

def upsert_strategy(version_code, name:, effective_at:, change_note:)
  s = ScoringStrategy.find_or_initialize_by(version_code: version_code)
  s.assign_attributes(
    name: name,
    effective_at: effective_at,
    rules_json: Scoring::Rules.default.to_h,
    change_note: change_note
  )
  s.publish! unless s.published?
  s.save!
  s
end

v1 = upsert_strategy(
  "v1.0-baseline",
  name: "Baseline post-rainfall priority v1.0",
  effective_at: V1_EFFECTIVE,
  change_note: "Initial baseline covering [2026-01-01, 2026-08-02)."
)

v2 = upsert_strategy(
  "v2.0-refined",
  name: "Refined post-rainfall priority v2.0",
  effective_at: V2_EFFECTIVE,
  change_note: "Becomes effective at 2026-08-02T00:00:00Z; v1 remains published for replay."
)

# --- Hazard points ----------------------------------------------------------

points_data = [
  {
    name: "切坡建房点 A",
    kind: "cut_slope_building",
    external_code: "HCS-001",
    road_accessible: true,
    rainfall: 186.0,
    history: 2,
    last_inspected_at: nil,
    snapshot_time: BOUNDARY - 6.hours,
    business_key: "evidence-hcs-001-20260801-1800",
    note: "从未巡查（last_inspected_at = NULL）；v1 快照"
  },
  {
    name: "道路边坡点 RDS-002",
    kind: "road_slope",
    external_code: "RDS-002",
    road_accessible: false,
    rainfall: 112.0,
    history: 0,
    last_inspected_at: BOUNDARY - 70.hours,
    snapshot_time: BOUNDARY - 6.hours,
    business_key: "evidence-rds-002-20260801-1800",
    note: "较早巡查，道路封闭；v1 快照"
  },
  {
    name: "登记隐患点 C",
    kind: "registered_hazard",
    external_code: "HRG-001",
    road_accessible: true,
    rainfall: 95.0,
    history: 1,
    last_inspected_at: BOUNDARY - 6.hours,
    snapshot_time: BOUNDARY - 6.hours,
    business_key: "evidence-hrg-001-20260801-1800",
    note: "当日已巡查；v1 快照"
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

  result = Scoring::SnapshotUpserter.call(point, {
    snapshot_time: data[:snapshot_time],
    rainfall_24h_mm: data[:rainfall],
    historical_event_count: data[:history],
    last_inspected_at: data[:last_inspected_at],
    road_accessible: data[:road_accessible],
    business_key: data[:business_key],
    source_note: data[:note],
    raw_payload: {
      rainfall_24h_mm: data[:rainfall],
      historical_event_count: data[:history],
      seed: true,
      bound_strategy: "v1"
    }
  })
  snap = result.snapshot
  snap.lock! unless snap.immutable?
  Scoring::PriorityComputer.call(snap, now: Time.current)
end

# --- RDS-002 boundary snapshot (binds to v2) --------------------------------

rds = HazardPoint.find_by!(external_code: "RDS-002")
boundary_snapshot = Scoring::SnapshotUpserter.call(rds, {
  snapshot_time: BOUNDARY,
  rainfall_24h_mm: 210.0,
  historical_event_count: 0,
  last_inspected_at: BOUNDARY - 70.hours,
  road_accessible: false,
  business_key: "evidence-rds-002-20260802-0000",
  source_note: "边界时刻新增快照，24h 降水 210mm，道路仍不可达；绑定 v2",
  raw_payload: {
    rainfall_24h_mm: 210.0,
    road_status: "closed",
    seed: true,
    bound_strategy: "v2"
  }
}).snapshot
boundary_snapshot.lock!
Scoring::PriorityComputer.call(boundary_snapshot, now: Time.current)

puts "Seeded v1 (#{v1.version_code}) and v2 (#{v2.version_code}), " \
     "#{HazardPoint.count} hazard points, #{EvidenceSnapshot.count} snapshots, " \
     "#{PriorityScore.count} priority scores."
