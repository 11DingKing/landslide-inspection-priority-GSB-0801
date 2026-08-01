module Api
  module V1
    class ScoringPoliciesController < ApplicationController
      def index
        policies = ScoringPolicy.order(effective_at: :desc)
        render json: policies.map { |p| serialize(p) }
      end

      def show
        policy = ScoringPolicy.find(params[:id])
        render json: serialize(policy)
      end

      def create
        policy = ScoringPolicy.create!(policy_params)
        render json: serialize(policy), status: :created
      end

      # Publishing is where the overlap rule bites. The model's publish! relies
      # on a DB partial-unique index; a second candidate at the same effective_at
      # instant raises Scoring::OverlappingPolicyError -> 409. The controller
      # itself makes no decision about which version wins.
      def publish
        policy = ScoringPolicy.find(params[:id])
        policy.publish!
        render json: serialize(policy)
      end

      private

      def policy_params
        params.require(:scoring_policy).permit(
          :version, :effective_at, definition: {}
        )
      end

      def serialize(policy)
        {
          id: policy.id,
          version: policy.version,
          status: policy.status,
          effective_at: policy.effective_at.utc.iso8601,
          published_at: policy.published_at&.utc&.iso8601,
          definition: policy.definition
        }
      end
    end
  end
end
