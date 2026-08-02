module Api
  module V1
    class PrioritiesController < BaseController
      before_action :set_hazard_point

      def show
        snapshot = @hazard_point.latest_snapshot
        if snapshot.nil?
          render json: { error: "not_found",
                         message: "no priority has been calculated for this hazard point" },
                 status: :not_found
          return
        end
        render json: SnapshotSerializer.one(snapshot, include_hazard: false)
      end

      def calculate
        at = parse_time(params[:at]) || Time.current
        strategy_version = params[:strategy_version]
        rainfall = params[:rainfall_24h_mm]
        business_id = params[:business_id]

        outcome = PriorityCalculator.call(
          @hazard_point,
          at: at,
          strategy_version: strategy_version,
          rainfall_24h_mm: rainfall,
          business_id: business_id
        )
        render json: SnapshotSerializer.one(outcome.snapshot, include_hazard: false),
               status: outcome.created ? :created : :ok
      end

      def explanation
        snapshot =
          if params[:snapshot_id].present?
            @hazard_point.evidence_snapshots.find(params[:snapshot_id])
          else
            @hazard_point.latest_snapshot
          end

        if snapshot.nil?
          render json: { error: "not_found",
                         message: "no priority snapshot exists for this hazard point" },
                 status: :not_found
          return
        end

        render json: {
          snapshot_id: snapshot.id,
          strategy_version: snapshot.strategy_version,
          total_score: snapshot.total_score,
          sum_of_items: snapshot.score_breakdown.sum { |i| i["score"] },
          risk_level: snapshot.risk_level,
          dispatch_status: snapshot.dispatch_status,
          score_breakdown: snapshot.score_breakdown,
          explanation: snapshot.explanation
        }
      end

      private

      def set_hazard_point
        @hazard_point = HazardPoint.find(params[:hazard_point_id] || params[:id])
      end

      def parse_time(value)
        return if value.blank?

        Time.iso8601(value)
      rescue ArgumentError
        raise ActionController::ParameterMissing, "at must be an ISO8601 timestamp"
      end
    end
  end
end
