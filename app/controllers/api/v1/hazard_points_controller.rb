module Api
  module V1
    class HazardPointsController < BaseController
      before_action :set_hazard_point, only: [:show, :update, :destroy]

      def index
        points = HazardPoint.order(:id).limit(200)
        render json: HazardPointSerializer.many(points)
      end

      def show
        render json: HazardPointSerializer.one(@hazard_point)
      end

      def create
        point = HazardPoint.create!(hazard_point_params)
        render json: HazardPointSerializer.one(point), status: :created
      end

      def update
        @hazard_point.update!(hazard_point_params)
        render json: HazardPointSerializer.one(@hazard_point)
      end

      def destroy
        @hazard_point.destroy!
        head :no_content
      end

      private

      def set_hazard_point
        @hazard_point = HazardPoint.find(params[:id])
      end

      def hazard_point_params
        params.require(:hazard_point).permit(
          :name, :point_type, :location, :road_accessible,
          :last_inspected_at, :historical_event_count,
          :latest_rainfall_24h_mm
        )
      end
    end
  end
end
