module Api
  module V1
    class HazardPointsController < ApplicationController
      def index
        points = HazardPoint.order(:code)
        render json: points.map { |p| serialize(p) }
      end

      def show
        point = HazardPoint.find(params[:id])
        render json: serialize(point)
      end

      def create
        point = HazardPoint.create!(hazard_point_params)
        render json: serialize(point), status: :created
      end

      private

      def hazard_point_params
        params.require(:hazard_point).permit(
          :code, :name, :category, :latitude, :longitude, :last_inspected_at
        )
      end

      def serialize(point)
        {
          id: point.id,
          code: point.code,
          name: point.name,
          category: point.category,
          latitude: point.latitude&.to_s,
          longitude: point.longitude&.to_s,
          last_inspected_at: point.last_inspected_at&.utc&.iso8601
        }
      end
    end
  end
end
