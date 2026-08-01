# frozen_string_literal: true

# Seeds the operational scenario:
#
#   * Scoring policy v1 covers [2026-01-01T00:00:00Z, 2026-08-02T00:00:00Z).
#   * Scoring policy v2 is published effective from the boundary
#     2026-08-02T00:00:00Z (open-ended). v1 is BOUNDED, not retired, so snapshots
#     captured before the boundary still resolve to v1 and remain replayable.
#   * Three reference hazard points with "today" snapshots (captured inside v1):
#       1. cut-slope housing  : 186 mm, 2 events, never inspected
#       2. road-side slope     : 112 mm, road CLOSED, inspected long ago
#       3. registered hazard   : 95 mm, 1 event, inspected today
#   * RDS-002 (the road slope) also gets a boundary snapshot at 2026-08-02
#     (business_key evidence-rds-002-20260802-0000, 210 mm, road still closed),
#     which falls inside v2's interval and therefore binds v2 and becomes the
#     current score for that point.
#
# Idempotent: safe to run repeatedly.

BOUNDARY = Time.utc(2026, 8, 2, 0, 0, 0)
V1_FROM  = Time.utc(2026, 1, 1, 0, 0, 0)
TODAY    = Time.utc(2026, 8, 1, 0, 0, 0) # inside v1's interval
LONG_AGO = Time.utc(2025, 6, 1, 0, 0, 0)

def upsert_policy!(version:, effective_from:, definition:)
  policy = ScoringPolicy.find_or_initialize_by(version: version)
  policy.effective_from = effective_from
  policy.definition = definition
  policy.save!
  policy.publish! unless policy.published?
  policy
end

v1_definition = {
  "rainfall" => { "thresholds" => [[0, 0], [50, 8], [80, 16], [100, 22], [120, 28], [150, 34], [180, 40]] },
  "history"  => { "thresholds" => [[0, 0], [1, 10], [2, 18], [3, 25]] },
  "recency"  => { "never_inspected" => 20, "thresholds" => [[0, 0], [7, 3], [30, 6], [90, 10], [180, 14], [365, 18]] },
  "exposure" => { "default" => 0, "by_category" => { "cut_slope_housing" => 15, "road_slope" => 10, "registered_hazard" => 7 } },
  "risk_bands" => [[0, "low"], [35, "moderate"], [60, "high"], [80, "extreme"]]
}

# v2 is a genuinely distinct version: the post-boundary strategy weighs road
# slopes slightly higher. Component names/ranges stay locked.
v2_definition = v1_definition.deep_dup
v2_definition["exposure"]["by_category"]["road_slope"] = 12

# Publish v1 open-ended first, then BOUND it at the boundary before publishing
# v2 — this is the "adjust v1's coverage, don't retire it" flow, and keeps the
# non-overlap exclusion constraint satisfied.
v1 = upsert_policy!(version: "2026.v1", effective_from: V1_FROM, definition: v1_definition)
v1.bound!(BOUNDARY) unless v1.effective_until == BOUNDARY
v2 = upsert_policy!(version: "2026.v2", effective_from: BOUNDARY, definition: v2_definition)

points = [
  {
    code: "HZ-CUTSLOPE-001", name: "切坡建房点", category: "cut_slope_housing",
    last_inspected_at: nil,
    snapshot: { captured_at: TODAY, rainfall_mm_24h: 186, historical_event_count: 2,
                road_accessible: true, point_last_inspected_at: nil }
  },
  {
    code: "RDS-002", name: "道路边坡点", category: "road_slope",
    last_inspected_at: LONG_AGO,
    snapshot: { captured_at: TODAY, rainfall_mm_24h: 112, historical_event_count: 0,
                road_accessible: false, point_last_inspected_at: LONG_AGO }
  },
  {
    code: "HZ-REGISTERED-003", name: "登记隐患点", category: "registered_hazard",
    last_inspected_at: TODAY,
    snapshot: { captured_at: TODAY, rainfall_mm_24h: 95, historical_event_count: 1,
                road_accessible: true, point_last_inspected_at: TODAY }
  }
]

points.each do |attrs|
  snapshot_attrs = attrs.delete(:snapshot)
  point = HazardPoint.find_or_create_by!(code: attrs[:code]) { |p| p.assign_attributes(attrs) }
  point.update!(attrs)

  snapshot = point.evidence_snapshots
                  .create_with(snapshot_attrs)
                  .find_or_create_by!(captured_at: snapshot_attrs[:captured_at])
  Scoring::Materializer.new(snapshot).call # binds v1 (captured inside v1)
end

# The boundary snapshot for RDS-002: idempotent by business_key, binds v2.
rds = HazardPoint.find_by!(code: "RDS-002")
boundary_snapshot = EvidenceSnapshot.capture!(
  hazard_point: rds,
  business_key: "evidence-rds-002-20260802-0000",
  captured_at: BOUNDARY,
  rainfall_mm_24h: 210,
  historical_event_count: 0,
  road_accessible: false, # road STILL closed -> blocked scheduling only
  point_last_inspected_at: LONG_AGO
)
Scoring::Materializer.new(boundary_snapshot).call # binds v2, becomes current for RDS-002

puts "Policies: #{ScoringPolicy.order(:effective_from).map { |p| "#{p.version} [#{p.effective_from.iso8601}, #{p.effective_until&.iso8601 || '∞'})" }.join(', ')}"
puts "Priority scores (current marked with *):"
PriorityScore.includes(:hazard_point).order(current: :desc, total_score: :desc).each do |ps|
  puts format("  %1s %-18s v=%-8s total=%3d risk=%-8s scheduling=%s",
              (ps.current ? "*" : " "), ps.hazard_point.code, ps.policy_version,
              ps.total_score, ps.risk_level, ps.scheduling_status)
end
