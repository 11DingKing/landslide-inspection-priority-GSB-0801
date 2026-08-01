class ApplicationController < ActionController::API
  # Domain-level error handling. Controllers stay thin: they translate domain
  # errors into HTTP, but hold no scoring logic themselves.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
  rescue_from ActiveRecord::RecordNotSaved, with: :render_conflict
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ArgumentError, with: :render_bad_request
  rescue_from Scoring::OverlappingPolicyError, with: :render_overlap_conflict
  rescue_from Scoring::ConflictingBusinessKeyError, with: :render_business_key_conflict
  rescue_from Scoring::NoAuthoritativePolicyError, with: :render_unprocessable

  private

  def render_not_found(error)
    render json: { error: "not_found", message: error.message }, status: :not_found
  end

  def render_unprocessable(error)
    render json: { error: "unprocessable_entity", message: error.message }, status: :unprocessable_entity
  end

  def render_conflict(error)
    render json: { error: "conflict", message: error.message }, status: :conflict
  end

  def render_overlap_conflict(error)
    render json: {
      error: "overlapping_policy",
      message: error.message,
      effective_from: error.effective_from&.utc&.iso8601,
      effective_until: error.effective_until&.utc&.iso8601
    }, status: :conflict
  end

  def render_business_key_conflict(error)
    render json: {
      error: "conflicting_business_key",
      message: error.message,
      business_key: error.business_key
    }, status: :conflict
  end

  def render_bad_request(error)
    render json: { error: "bad_request", message: error.message }, status: :bad_request
  end
end
