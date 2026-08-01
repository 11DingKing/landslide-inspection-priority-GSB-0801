# frozen_string_literal: true

module Api
  module V1
    class HazardPointsController < ApplicationController
      def index
        points = HazardPoint.order(:id).limit(500)
        render json: points.map { |p| serialize(p) }
      end

      def create
        point = HazardPoint.create!(point_params)
        render json: serialize(point), status: :created
      end

      private

      def point_params
        params.expect(hazard_point: %i[external_code name kind])
      end

      def serialize(point)
        {
          "id" => point.id,
          "external_code" => point.external_code,
          "name" => point.name,
          "kind" => point.kind
        }
      end
    end
  end
end
