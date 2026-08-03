module Api
  module V1
    # The priority surface: compute (materialise a score), queue (ordered
    # retrieval) and explain (per-component breakdown). All scoring is delegated
    # to Scoring::* services; this controller only wires HTTP to the domain.
    class PrioritiesController < ApplicationController
      # POST /api/v1/evidence_snapshots/:evidence_snapshot_id/priority
      # Computes against the authoritative policy for the snapshot instant, or a
      # specific policy when replaying a historical version.
      def compute
        snapshot = EvidenceSnapshot.find(params[:evidence_snapshot_id])
        policy = resolve_policy
        outcome = Scoring::Materializer.new(snapshot).call(policy: policy)
        render json: Scoring::Presenter.explanation(outcome.priority_score), status: :created
      end

      # GET /api/v1/scoring_policies/:scoring_policy_id/queue
      # Keyset-paginated, stable-ordered inspection queue for one policy version.
      def queue
        policy = ScoringPolicy.find(params[:scoring_policy_id])
        page = Scoring::Queue.new(policy: policy).page(
          limit: params[:limit],
          cursor: params[:cursor],
          scheduling_status: params[:scheduling_status],
          current: params[:current]
        )
        render json: page.to_h
      end

      # GET /api/v1/priority_scores/:id/explanation
      def explain
        score = PriorityScore.find(params[:id])
        render json: Scoring::Presenter.explanation(score)
      end

      private

      def resolve_policy
        return nil if params[:scoring_policy_id].blank?

        ScoringPolicy.find(params[:scoring_policy_id])
      end
    end
  end
end
