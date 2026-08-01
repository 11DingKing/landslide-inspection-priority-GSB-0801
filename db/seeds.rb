# frozen_string_literal: true

# Seed data: strategy v1 + the three pre-registered hazard points with their
# immutable evidence snapshots, then compute the current priority of each.

RULES_V1 = {
  "rainfall_24h" => {
    "thresholds" => [
      { "gte_mm" => 150, "score" => 40 },
      { "gte_mm" => 100, "score" => 30 },
      { "gte_mm" => 50,  "score" => 20 },
      { "gte_mm" => 25,  "score" => 10 }
    ]
  },
  "historical_events" => { "per_event" => 15, "cap_events" => 2 },
  "inspection_recency" => {
    "never" => 30,
    "stale_days" => [
      { "gte_days" => 90, "score" => 25 },
      { "gte_days" => 30, "score" => 15 },
      { "gte_days" => 7,  "score" => 5 }
    ],
    "fresh" => 0
  },
  "risk_levels" => [
    { "min_total" => 70, "level" => "high" },
    { "min_total" => 40, "level" => "medium" }
  ]
}.freeze

strategy = StrategyVersion.find_or_initialize_by(version: 1)
if strategy.new_record?
  strategy.assign_attributes(
    rules: RULES_V1,
    effective_range: StrategyVersion.compose_range(Time.zone.parse("2026-01-01 00:00:00"), nil),
    status: "published",
    published_at: Time.current
  )
  strategy.save!
end

captured_at = Time.current

SEED_POINTS = [
  # 切坡建房点：24h 降水 186mm，2 次历史事件，最近巡查时间为空
  { external_code: "SLP-001", name: "切坡建房点", kind: "cut_slope_building",
    rainfall_24h_mm: 186, historical_event_count: 2,
    last_inspected_at: nil, road_accessible: true },
  # 道路边坡点：112mm，道路关闭（不可达），最近巡查时间较早（90 天前）
  { external_code: "RDS-002", name: "道路边坡点", kind: "road_slope",
    rainfall_24h_mm: 112, historical_event_count: 0,
    last_inspected_at: captured_at - 90.days, road_accessible: false },
  # 登记隐患点：95mm，1 次历史事件，最近巡查时间为当日
  { external_code: "REG-003", name: "登记隐患点", kind: "registered_hazard",
    rainfall_24h_mm: 95, historical_event_count: 1,
    last_inspected_at: captured_at, road_accessible: true }
].freeze

SEED_POINTS.each do |attrs|
  point = HazardPoint.find_or_create_by!(external_code: attrs[:external_code]) do |p|
    p.name = attrs[:name]
    p.kind = attrs[:kind]
  end

  snapshot = point.evidence_snapshots.order(:captured_at).last
  snapshot ||= point.evidence_snapshots.create!(
    rainfall_24h_mm: attrs[:rainfall_24h_mm],
    historical_event_count: attrs[:historical_event_count],
    last_inspected_at: attrs[:last_inspected_at],
    road_accessible: attrs[:road_accessible],
    captured_at: captured_at,
    note: "seed evidence"
  )

  record = PriorityCalculator.call(snapshot: snapshot)
  puts format("%-12s total=%3d risk=%-6s status=%s components=%s (strategy v%d)",
              point.external_code, record.total_score, record.risk_level,
              record.scheduling_status, record.components.to_json,
              record.strategy_version.version)
end
