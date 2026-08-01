module Api
  module V1
    class BaseController < ActionController::API
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
      rescue_from ActionController::ParameterMissing, with: :bad_request
      rescue_from ScoringEngine::InvalidRules, with: :unprocessable
      rescue_from PriorityCalculator::MissingStrategy, with: :conflict
      rescue_from StrategyManager::OverlappingStrategy, with: :conflict
      rescue_from StrategyResolver::NoActiveStrategy, with: :conflict
      rescue_from QueueRetriever::Error, with: :bad_request

      private

      def not_found(error)
        render json: { error: "not_found", message: error.message }, status: :not_found
      end

      def unprocessable(error)
        message = error.respond_to?(:record) && error.record ?
                    error.record.errors.full_messages.join("; ") : error.message
        render json: { error: "unprocessable_entity", message: message },
               status: :unprocessable_entity
      end

      def bad_request(error)
        render json: { error: "bad_request", message: error.message }, status: :bad_request
      end

      def conflict(error)
        render json: { error: "conflict", message: error.message }, status: :conflict
      end
    end
  end
end
