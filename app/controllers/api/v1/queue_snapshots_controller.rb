module Api
  module V1
    # Named, immutable queue-read snapshots. Creating one freezes a policy's
    # current ranking; reading one paginates the frozen items with stable keyset
    # cursors, unaffected by later `current` movement. This controller only wires
    # HTTP to the Scoring::QueueSnapshot* services.
    class QueueSnapshotsController < ApplicationController
      # POST /api/v1/scoring_policies/:scoring_policy_id/queue_snapshots
      # Pins the snapshot to the given policy ("round").
      def create
        policy = ScoringPolicy.find(params[:scoring_policy_id])
        snapshot = Scoring::QueueSnapshotBuilder.new(
          policy: policy, name: params.require(:name)
        ).call
        render json: serialize(snapshot), status: :created
      end

      # GET /api/v1/queue_snapshots/:id  (id may be numeric id or the name)
      def show
        render json: serialize(find_snapshot)
      end

      # GET /api/v1/queue_snapshots/:id/page?cursor=&limit=
      def page
        snapshot = find_snapshot
        page = Scoring::QueueSnapshotReader.new(snapshot).page(
          limit: params[:limit], cursor: params[:cursor]
        )
        render json: { queue_snapshot: snapshot.name }.merge(page.to_h)
      end

      private

      def find_snapshot
        key = params[:id]
        if key.to_s.match?(/\A\d+\z/)
          QueueSnapshot.find(key)
        else
          QueueSnapshot.find_by!(name: key)
        end
      end

      def serialize(snapshot)
        {
          id: snapshot.id,
          name: snapshot.name,
          scoring_policy_id: snapshot.scoring_policy_id,
          policy_version: snapshot.scoring_policy.version,
          built_at: snapshot.built_at.utc.iso8601,
          item_count: snapshot.items.count
        }
      end
    end
  end
end
