class StrategiesController < ApplicationController
  before_action :set_strategy, only: %i[show publish retire]

  def index
    strategies = ScoringStrategy.order(effective_at: :desc, id: :desc).limit(200)
    render json: strategies
  end

  def show
    render json: @strategy
  end

  def create
    strategy = ScoringStrategy.create!(strategy_params)
    render json: strategy, status: :created
  end

  def publish
    @strategy.publish!(Time.current)
    render json: @strategy
  end

  def retire
    @strategy.update!(status: "retired")
    render json: @strategy
  end

  private

  def set_strategy
    @strategy = ScoringStrategy.find(params[:id])
  end

  def strategy_params
    params.require(:strategy).permit(
      :name, :version_code, :effective_at, :change_note,
      rules_json: {}
    )
  end
end
