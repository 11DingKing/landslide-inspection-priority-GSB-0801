# Idempotently ensure the v1 published strategy exists.
strategy = ScoringStrategy.find_by(version: 1)
if strategy.nil?
  strategy = StrategyManager.publish!(
    name: "地灾巡查优先级 v1",
    description: "基于降水、历史事件、点位类型与巡查时效的默认评分策略",
    effective_at: Time.current.beginning_of_day,
    rules: ScoringRules::V1.rules
  )
  puts "Created published strategy v#{strategy.version} (id=#{strategy.id})"
else
  puts "Strategy v#{strategy.version} already exists (id=#{strategy.id})"
end

# The three required seed hazard points.
today = Date.current

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
    last_inspected_at: 2.days.ago.midnight
  },
  {
    name: "登记隐患点 C",
    point_type: "registered_hazard",
    location: "河谷安置区北侧",
    latest_rainfall_24h_mm: 95.0,
    historical_event_count: 1,
    road_accessible: true,
    last_inspected_at: today.in_time_zone("UTC").beginning_of_day + 9.hours
  }
]

points = point_definitions.map do |attrs|
  HazardPoint.find_or_create_by!(name: attrs[:name]) do |p|
    p.assign_attributes(attrs)
  end
end

# Calculate today's priority snapshot for each point (idempotent: one per day).
points.each do |point|
  existing = point.evidence_snapshots
                  .where("snapshot_at >= ?", today.beginning_of_day)
                  .first
  next if existing

  snapshot = PriorityCalculator.call(point, at: Time.current)
  puts "Calculated priority for #{point.name}: " \
       "score=#{snapshot.total_score} risk=#{snapshot.risk_level} " \
       "dispatch=#{snapshot.dispatch_status} strategy=v#{snapshot.strategy_version}"
end

puts "Seeding complete."
