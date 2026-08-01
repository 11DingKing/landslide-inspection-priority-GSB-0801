class HazardPointSerializer
  def self.one(point)
    {
      id: point.id,
      name: point.name,
      point_type: point.point_type,
      location: point.location,
      road_accessible: point.road_accessible,
      road_status: point.road_status,
      road_closed_at: point.road_closed_at&.iso8601,
      last_inspected_at: point.last_inspected_at&.iso8601,
      historical_event_count: point.historical_event_count,
      latest_rainfall_24h_mm: point.latest_rainfall_24h_mm.to_f,
      created_at: point.created_at.iso8601,
      updated_at: point.updated_at.iso8601
    }
  end

  def self.many(points)
    points.map { |p| one(p) }
  end
end
