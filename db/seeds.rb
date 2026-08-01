# frozen_string_literal: true

# Seeds three reference hazard points from the operational scenario plus a
# baseline published scoring policy, then materialises today's priority scores.
#
#   1. cut-slope self-built housing : 186 mm / 24h, 2 historical events, never inspected
#   2. road-side slope              : 112 mm / 24h, road CLOSED, inspected long ago
#   3. registered hazard point      : 95 mm / 24h, 1 historical event, inspected today
#
# Idempotent: safe to run repeatedly.

now = Time.zone.now
captured_at = now

baseline = ScoringPolicy.find_or_initialize_by(version: "2026.08.01-baseline")
baseline.assign_attributes(
  effective_at: now - 1.hour,
  definition: {
    "rainfall" => {
      "thresholds" => [[0, 0], [50, 8], [80, 16], [100, 22], [120, 28], [150, 34], [180, 40]]
    },
    "history" => {
      "thresholds" => [[0, 0], [1, 10], [2, 18], [3, 25]]
    },
    "recency" => {
      "never_inspected" => 20,
      "thresholds" => [[0, 0], [7, 3], [30, 6], [90, 10], [180, 14], [365, 18]]
    },
    "exposure" => {
      "default" => 0,
      "by_category" => {
        "cut_slope_housing" => 15,
        "road_slope" => 10,
        "registered_hazard" => 7
      }
    },
    "risk_bands" => [[0, "low"], [35, "moderate"], [60, "high"], [80, "extreme"]]
  }
)
baseline.save!
baseline.publish! unless baseline.published?

points = [
  {
    code: "HZ-CUTSLOPE-001",
    name: "切坡建房点",
    category: "cut_slope_housing",
    last_inspected_at: nil,
    snapshot: {
      rainfall_mm_24h: 186,
      historical_event_count: 2,
      road_accessible: true,
      point_last_inspected_at: nil
    }
  },
  {
    code: "HZ-ROADSLOPE-002",
    name: "道路边坡点",
    category: "road_slope",
    last_inspected_at: now - 400.days,
    snapshot: {
      rainfall_mm_24h: 112,
      historical_event_count: 0,
      road_accessible: false, # road closed -> blocked scheduling, risk preserved
      point_last_inspected_at: now - 400.days
    }
  },
  {
    code: "HZ-REGISTERED-003",
    name: "登记隐患点",
    category: "registered_hazard",
    last_inspected_at: now,
    snapshot: {
      rainfall_mm_24h: 95,
      historical_event_count: 1,
      road_accessible: true,
      point_last_inspected_at: now
    }
  }
]

points.each do |attrs|
  snapshot_attrs = attrs.delete(:snapshot)
  point = HazardPoint.find_or_create_by!(code: attrs[:code]) do |p|
    p.assign_attributes(attrs)
  end
  point.update!(attrs)

  snapshot = point.evidence_snapshots
                  .create_with(snapshot_attrs)
                  .find_or_create_by!(captured_at: captured_at)

  Scoring::Materializer.new(snapshot).call
end

puts "Seeded #{HazardPoint.count} hazard points, policy #{baseline.version}."
PriorityScore.where(scoring_policy_id: baseline.id).queue_ordered.each do |ps|
  puts format(
    "  %-20s total=%3d risk=%-8s scheduling=%s",
    ps.hazard_point.code, ps.total_score, ps.risk_level, ps.scheduling_status
  )
end
