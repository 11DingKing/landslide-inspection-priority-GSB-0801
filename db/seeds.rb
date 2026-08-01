# frozen_string_literal: true

# Seed data: a traceable strategy timeline (v1 -> v2), the three
# pre-registered hazard points with their immutable evidence snapshots,
# the boundary snapshot for RDS-002, and the current priority of each point.
#
# Timeline (half-open ranges, adjacency enforced by the exclusion constraint):
#   v1: [2026-01-01T00:00:00Z, 2026-08-02T00:00:00Z)
#   v2: [2026-08-02T00:00:00Z, infinity)
# v1 stays PUBLISHED — old snapshots keep resolving to it and replays
# reproduce yesterday's judgments exactly.

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

# v2 refines the extreme-rainfall band (150mm band scores 38, new 200mm band
# scores 40). Component names and ranges remain the locked ones.
RULES_V2 = RULES_V1.deep_merge(
  "rainfall_24h" => {
    "thresholds" => [
      { "gte_mm" => 200, "score" => 40 },
      { "gte_mm" => 150, "score" => 38 },
      { "gte_mm" => 100, "score" => 30 },
      { "gte_mm" => 50,  "score" => 20 },
      { "gte_mm" => 25,  "score" => 10 }
    ]
  }
).freeze

TIMELINE = {
  1 => { rules: RULES_V1, from: Time.zone.parse("2026-01-01 00:00:00 UTC"),
         to: Time.zone.parse("2026-08-02 00:00:00 UTC") },
  2 => { rules: RULES_V2, from: Time.zone.parse("2026-08-02 00:00:00 UTC"), to: nil }
}.freeze

# Publish in version order: narrowing v1 first releases the upper range so
# v2 can be published adjacently without violating the overlap constraint.
TIMELINE.each do |version_number, spec|
  strategy = StrategyVersion.find_or_initialize_by(version: version_number)
  strategy.rules = spec[:rules]
  strategy.effective_range = StrategyVersion.compose_range(spec[:from], spec[:to])
  if strategy.new_record?
    strategy.status = "published"
    strategy.published_at = Time.current
    strategy.save!
  else
    strategy.save!
    strategy.publish! unless strategy.status == "published"
  end
end

# Fixed capture time keeps the seeds idempotent: re-running db:seed finds the
# snapshots by client_reference and verifies identical content.
captured_at = Time.zone.parse("2026-08-01 08:00:00 UTC")

SEED_POINTS = [
  # 切坡建房点：24h 降水 186mm，2 次历史事件，最近巡查时间为空
  { external_code: "SLP-001", name: "切坡建房点", kind: "cut_slope_building",
    client_reference: "evidence-slp-001-seed",
    rainfall_24h_mm: 186, historical_event_count: 2,
    last_inspected_at: nil, road_accessible: true, captured_at: captured_at },
  # 道路边坡点：112mm，道路关闭（不可达），最近巡查时间较早（90 天前）
  { external_code: "RDS-002", name: "道路边坡点", kind: "road_slope",
    client_reference: "evidence-rds-002-seed",
    rainfall_24h_mm: 112, historical_event_count: 0,
    last_inspected_at: captured_at - 90.days, road_accessible: false,
    captured_at: captured_at },
  # 登记隐患点：95mm，1 次历史事件，最近巡查时间为当日
  { external_code: "REG-003", name: "登记隐患点", kind: "registered_hazard",
    client_reference: "evidence-reg-003-seed",
    rainfall_24h_mm: 95, historical_event_count: 1,
    last_inspected_at: captured_at, road_accessible: true,
    captured_at: captured_at },
  # RDS-002 边界快照：恰好采集于 v1/v2 切换时刻 2026-08-02T00:00:00Z，
  # 210mm，道路仍不可达 -> 必须绑定 v2，blocked 且风险分数不受影响
  { external_code: "RDS-002", name: "道路边坡点", kind: "road_slope",
    client_reference: "evidence-rds-002-20260802-0000",
    rainfall_24h_mm: 210, historical_event_count: 0,
    last_inspected_at: Time.zone.parse("2026-05-04 00:00:00 UTC"),
    road_accessible: false,
    captured_at: Time.zone.parse("2026-08-02 00:00:00 UTC") }
].freeze

SEED_POINTS.each do |attrs|
  point = HazardPoint.find_or_create_by!(external_code: attrs[:external_code]) do |p|
    p.name = attrs[:name]
    p.kind = attrs[:kind]
  end

  snapshot = EvidenceSnapshot.find_by(client_reference: attrs[:client_reference])
  unless snapshot&.same_evidence?(attrs)
    raise "seed snapshot #{attrs[:client_reference]} conflicts with existing data" if snapshot

    snapshot = point.evidence_snapshots.create!(
      attrs.slice(:rainfall_24h_mm, :historical_event_count, :last_inspected_at,
                  :road_accessible, :captured_at, :client_reference)
           .merge(note: "seed evidence")
    )
  end

  record = PriorityCalculator.call(snapshot: snapshot)
  puts format("%-28s total=%3d risk=%-6s status=%-11s strategy=v%d components=%s",
              attrs[:client_reference], record.total_score, record.risk_level,
              record.scheduling_status, record.strategy_version.version,
              record.components.to_json)
end

# Named queue read snapshot: pins the strategy round (round 2 == v2, since
# the snapshot is taken at the 2026-08-02 boundary) and the current
# membership, so cursor traversals stay stable across later recomputations.
queue_snapshot = QueueSnapshot.find_by(name: "queue-20260802-01")
if queue_snapshot.nil?
  queue_snapshot = QueueSnapshot.capture!(
    name: "queue-20260802-01",
    at: Time.zone.parse("2026-08-02 00:00:00 UTC")
  )
end
puts format("queue snapshot %-20s entries=%d strategy=v%d",
            queue_snapshot.name, queue_snapshot.entry_count,
            queue_snapshot.strategy_version.version)
