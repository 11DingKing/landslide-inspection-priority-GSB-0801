module Api
  module V1
    class ScoringPoliciesController < ApplicationController
      def index
        policies = ScoringPolicy.order(effective_from: :desc)
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

      # Publishing enforces the interval-overlap rule at the DB level (a GiST
      # exclusion constraint). A candidate whose [from, until) window overlaps an
      # already-published policy raises Scoring::OverlappingPolicyError -> 409.
      # The controller makes no decision about which version wins.
      def publish
        policy = ScoringPolicy.find(params[:id])
        policy.publish!
        render json: serialize(policy)
      end

      # Bound an already-published policy's interval (set effective_until) so a
      # successor can take over from that instant WITHOUT retiring the policy —
      # snapshots captured before the boundary still resolve to it and remain
      # replayable.
      def bound
        policy = ScoringPolicy.find(params[:id])
        policy.bound!(bound_params[:effective_until])
        render json: serialize(policy)
      end

      private

      def policy_params
        params.require(:scoring_policy).permit(
          :version, :effective_from, :effective_until, definition: {}
        )
      end

      def bound_params
        params.require(:scoring_policy).permit(:effective_until)
      end

      def serialize(policy)
        {
          id: policy.id,
          version: policy.version,
          status: policy.status,
          effective_from: policy.effective_from.utc.iso8601,
          effective_until: policy.effective_until&.utc&.iso8601,
          published_at: policy.published_at&.utc&.iso8601,
          definition: policy.definition
        }
      end
    end
  end
end
