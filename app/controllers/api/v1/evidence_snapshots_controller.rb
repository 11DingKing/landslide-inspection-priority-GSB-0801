module Api
  module V1
    class EvidenceSnapshotsController < ApplicationController
      # Snapshots are immutable: only create + read are exposed. There is no
      # update or destroy route by design.
      def index
        point = HazardPoint.find(params[:hazard_point_id])
        snapshots = point.evidence_snapshots.order(captured_at: :desc)
        render json: snapshots.map { |s| serialize(s) }
      end

      def show
        snapshot = EvidenceSnapshot.find(params[:id])
        render json: serialize(snapshot)
      end

      def create
        point = HazardPoint.find(params[:hazard_point_id])
        snapshot = point.evidence_snapshots.create!(snapshot_params)
        render json: serialize(snapshot), status: :created
      end

      private

      def snapshot_params
        params.require(:evidence_snapshot).permit(
          :captured_at, :rainfall_mm_24h, :historical_event_count,
          :road_accessible, :point_last_inspected_at
        )
      end

      def serialize(snapshot)
        {
          id: snapshot.id,
          hazard_point_id: snapshot.hazard_point_id,
          captured_at: snapshot.captured_at.utc.iso8601,
          rainfall_mm_24h: snapshot.rainfall_mm_24h.to_s("F"),
          historical_event_count: snapshot.historical_event_count,
          road_accessible: snapshot.road_accessible,
          point_last_inspected_at: snapshot.point_last_inspected_at&.utc&.iso8601,
          content_digest: snapshot.content_digest
        }
      end
    end
  end
end
