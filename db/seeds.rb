# Temporal boundaries:
#   v1 effective from 2026-01-01T00:00:00Z
#   v2 effective from 2026-08-02T00:00:00Z (the cutover boundary)
v1_start = Time.utc(2026, 1, 1, 0, 0, 0)
v2_boundary = Time.utc(2026, 8, 2, 0, 0, 0)
old_snapshot_at = Time.utc(2026, 8, 1, 12, 0, 0)

# Idempotently ensure published strategies. v1 stays published (never retired)
# so old snapshots remain bound to it and can be replayed.
v1 = ScoringStrategy.find_by(version: 1)
if v1.nil?
  v1 = StrategyManager.publish!(
    name: "地灾巡查优先级 v1",
    description: "覆盖 [2026-01-01, 2026-08-02) 的默认评分策略",
    effective_at: v1_start,
    rules: ScoringRules::V1.rules
  )
  puts "Created published strategy v#{v1.version} (effective #{v1.effective_at.iso8601})"
else
  puts "Strategy v#{v1.version} already exists (effective #{v1.effective_at.iso8601})"
end

v2 = ScoringStrategy.find_by(version: 2)
if v2.nil?
  v2 = StrategyManager.publish!(
    name: "地灾巡查优先级 v2",
    description: "自 2026-08-02T00:00:00Z 边界时刻起生效的评分策略",
    effective_at: v2_boundary,
    rules: ScoringRules::V2.rules
  )
  puts "Created published strategy v#{v2.version} (effective #{v2.effective_at.iso8601})"
else
  puts "Strategy v#{v2.version} already exists (effective #{v2.effective_at.iso8601})"
end

# Original three points: their snapshots are taken BEFORE the boundary, so they
# bind to v1 regardless of when the seed runs.
point_definitions = [
  {
    name: "切坡建房点 A",
    point_type: "cut_slope_building",
    location: "青山村 3 组",
    latest_rainfall_24h_mm: 186.0,
    historical_event_count: 2,
    road_accessible: true,
    last_inspected_at: nil
  },
  {
    name: "道路边坡点 B",
    point_type: "road_slope",
    location: "县道 X705 K12+300",
    latest_rainfall_24h_mm: 112.0,
    historical_event_count: 0,
    road_accessible: false,
    last_inspected_at: Time.utc(2026, 7, 30, 0, 0, 0)
  },
  {
    name: "登记隐患点 C",
    point_type: "registered_hazard",
    location: "河谷安置区北侧",
    latest_rainfall_24h_mm: 95.0,
    historical_event_count: 1,
    road_accessible: true,
    last_inspected_at: Time.utc(2026, 8, 1, 9, 0, 0)
  }
]

points = point_definitions.map do |attrs|
  HazardPoint.find_or_create_by!(name: attrs[:name]) do |p|
    p.assign_attributes(attrs)
  end
end

points.each do |point|
  existing = point.evidence_snapshots.find_by(snapshot_at: old_snapshot_at)
  next if existing

  outcome = PriorityCalculator.call(point, at: old_snapshot_at)
  snapshot = outcome.snapshot
  puts "v1 snapshot for #{point.name}: score=#{snapshot.total_score} " \
       "risk=#{snapshot.risk_level} dispatch=#{snapshot.dispatch_status} " \
       "strategy=v#{snapshot.strategy_version}"
end

# RDS-002: new road-slope point, road still unreachable, 210mm in 24h.
# Snapshot is taken exactly at the boundary and binds to v2. It uses a stable
# business identifier so repeated submissions are idempotent.
rds002 = HazardPoint.find_or_create_by!(name: "道路边坡点 RDS-002") do |p|
  p.point_type = "road_slope"
  p.location = "RDS-002"
  p.latest_rainfall_24h_mm = 210.0
  p.historical_event_count = 0
  p.road_accessible = false
  p.last_inspected_at = nil
end

business_id = "evidence-rds-002-20260802-0000"
existing = EvidenceSnapshot.find_by(business_id: business_id)
unless existing
  outcome = PriorityCalculator.call(
    rds002,
    at: v2_boundary,
    rainfall_24h_mm: 210.0,
    business_id: business_id
  )
  snapshot = outcome.snapshot
  puts "v2 snapshot for #{rds002.name}: score=#{snapshot.total_score} " \
       "risk=#{snapshot.risk_level} dispatch=#{snapshot.dispatch_status} " \
       "strategy=v#{snapshot.strategy_version} business_id=#{snapshot.business_id}"
end

puts "Seeding complete."
