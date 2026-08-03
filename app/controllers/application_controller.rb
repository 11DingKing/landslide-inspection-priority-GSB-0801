class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
  rescue_from ActiveRecord::RecordNotUnique, with: :conflict
  rescue_from Scoring::StrategySelector::NoStrategyError, with: :no_strategy
  rescue_from ScoringStrategy::StrategyOverlapError, with: :strategy_overlap
  rescue_from Scoring::PriorityComputer::ComponentSumMismatch, with: :server_error
  rescue_from Scoring::SnapshotUpserter::PayloadConflict, with: :payload_conflict

  private

  def not_found(e)
    render json: { error: "not_found", message: e.message }, status: :not_found
  end

  def unprocessable(e)
    render json: { error: "unprocessable_entity",
                   message: e.message,
                   details: e.record&.errors&.messages },
           status: :unprocessable_entity
  end

  def no_strategy(e)
    render json: { error: "no_strategy", message: e.message },
           status: :service_unavailable
  end

  def strategy_overlap(e)
    render json: { error: "strategy_overlap", message: e.message },
           status: :conflict
  end

  def payload_conflict(e)
    render json: {
      error: "payload_conflict",
      message: e.message,
      existing_snapshot_id: e.existing.id,
      business_key: e.existing.business_key
    }, status: :conflict
  end

  def conflict(e)
    render json: { error: "conflict", message: e.message },
           status: :conflict
  end

  def server_error(e)
    render json: { error: "invariant_violation", message: e.message },
           status: :internal_server_error
  end
end
