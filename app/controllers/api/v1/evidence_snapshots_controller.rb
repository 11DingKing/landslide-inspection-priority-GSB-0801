# frozen_string_literal: true

module Api
  module V1
    class EvidenceSnapshotsController < ApplicationController
      def create
        point = HazardPoint.find(params[:hazard_point_id])
        snapshot = point.evidence_snapshots.create!(snapshot_params)
        render json: serialize(snapshot), status: :created
      end

      private

      def snapshot_params
        params.expect(evidence_snapshot: %i[rainfall_24h_mm historical_event_count
                                            last_inspected_at road_accessible
                                            captured_at note])
      end

      def serialize(snapshot)
        {
          "id" => snapshot.id,
          "hazard_point_id" => snapshot.hazard_point_id,
          "rainfall_24h_mm" => snapshot.rainfall_24h_mm.to_s,
          "historical_event_count" => snapshot.historical_event_count,
          "last_inspected_at" => snapshot.last_inspected_at&.iso8601,
          "road_accessible" => snapshot.road_accessible,
          "captured_at" => snapshot.captured_at.iso8601,
          "note" => snapshot.note
        }
      end
    end
  end
end
