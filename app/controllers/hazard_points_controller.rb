class HazardPointsController < ApplicationController
  before_action :set_hazard_point, only: %i[show update]

  def index
    points = HazardPoint.ordered.limit(200)
    render json: points
  end

  def show
    render json: @hazard_point
  end

  def create
    point = HazardPoint.create!(point_params)
    render json: point, status: :created
  end

  def update
    @hazard_point.update!(point_params)
    render json: @hazard_point
  end

  private

  def set_hazard_point
    @hazard_point = HazardPoint.find(params[:id])
  end

  def point_params
    params.require(:hazard_point).permit(
      :kind, :name, :description, :latitude, :longitude,
      :external_code, :road_accessible
    )
  end
end
