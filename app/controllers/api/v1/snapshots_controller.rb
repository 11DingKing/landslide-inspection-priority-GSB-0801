module Api
  module V1
    class SnapshotsController < BaseController
      before_action :set_snapshot, only: [:show, :replay]

      def index
        scope = EvidenceSnapshot.order(snapshot_at: :desc, id: :desc)
        scope = scope.where(hazard_point_id: params[:hazard_point_id]) if params[:hazard_point_id]
        scope = scope.joins(:scoring_strategy)
                     .where(scoring_strategies: { version: params[:strategy_version] }) if params[:strategy_version]
        snapshots = scope.limit(200)
        render json: SnapshotSerializer.many(snapshots)
      end

      def show
        render json: SnapshotSerializer.one(@snapshot)
      end

      def replay
        strategy_version = params.require(:strategy_version)
        new_snapshot = PriorityCalculator.replay(@snapshot, strategy_version: strategy_version)
        render json: SnapshotSerializer.one(new_snapshot), status: :created
      end

      private

      def set_snapshot
        @snapshot = EvidenceSnapshot.find(params[:id])
      end
    end
  end
end
