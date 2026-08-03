class SnapshotSerializer
  def self.one(snapshot, include_hazard: true)
    data = {
      id: snapshot.id,
      hazard_point_id: snapshot.hazard_point_id,
      business_id: snapshot.business_id,
      snapshot_at: snapshot.snapshot_at.iso8601,
      evidence: {
        rainfall_24h_mm: snapshot.rainfall_24h_mm.to_f,
        historical_event_count: snapshot.historical_event_count,
        point_type: snapshot.point_type,
        road_status: snapshot.road_status,
        last_inspected_at: snapshot.last_inspected_at&.iso8601
      },
      scoring: {
        strategy_version: snapshot.strategy_version,
        total_score: snapshot.total_score,
        risk_level: snapshot.risk_level,
        dispatch_status: snapshot.dispatch_status,
        score_breakdown: snapshot.score_breakdown.map do |item|
          {
            key: item["key"],
            name: item["name"],
            score: item["score"],
            max: item["max"],
            reason: item["reason"]
          }
        end
      },
      explanation: snapshot.explanation,
      immutable: true,
      created_at: snapshot.created_at.iso8601
    }

    if include_hazard && snapshot.association(:hazard_point).loaded? && snapshot.hazard_point
      data[:hazard_point] = HazardPointSerializer.one(snapshot.hazard_point)
    end
    data
  end

  def self.many(snapshots)
    snapshots.map { |s| one(s) }
  end
end
