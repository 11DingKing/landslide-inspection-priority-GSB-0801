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
        attrs = snapshot_params.to_h.symbolize_keys
        business_key = attrs.delete(:business_key)
        snapshot = EvidenceSnapshot.capture!(
          hazard_point: point, business_key: business_key, **attrs
        )
        render json: serialize(snapshot), status: :created
      end

      private

      def snapshot_params
        params.require(:evidence_snapshot).permit(
          :captured_at, :rainfall_mm_24h, :historical_event_count,
          :road_accessible, :point_last_inspected_at, :business_key
        )
      end

      def serialize(snapshot)
        {
          id: snapshot.id,
          hazard_point_id: snapshot.hazard_point_id,
          business_key: snapshot.business_key,
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
