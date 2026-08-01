# frozen_string_literal: true

class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
  rescue_from PriorityCalculator::NoApplicableStrategy do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::ExclusionViolation do
    render json: { error: "a published strategy version already covers this effective range" },
           status: :conflict
  end

  private

  def render_not_found(error)
    render json: { error: error.message }, status: :not_found
  end

  def render_unprocessable(error)
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end
end
