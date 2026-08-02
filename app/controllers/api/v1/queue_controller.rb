module Api
  module V1
    class QueueController < BaseController
      def index
        queue_read = resolve_queue_read
        page = QueueRetriever.call(
          limit: params[:limit],
          cursor: params[:cursor],
          dispatch_status: params[:dispatch_status],
          include_blocked: params[:include_blocked] != "false",
          strategy_version: params[:strategy_version],
          queue_read: queue_read
        )

        render json: {
          queue: page.items.map { |s| queue_item(s) },
          meta: {
            total_count: page.total_count,
            next_cursor: page.next_cursor,
            limit: normalize_limit,
            queue_read: queue_read && {
              business_id: queue_read.business_id,
              strategy_version: queue_read.strategy_version,
              cutoff_at: queue_read.cutoff_at.iso8601
            }
          }
        }
      end

      private

      def resolve_queue_read
        return if params[:queue_read].blank?

        QueueRead.find_by!(business_id: params[:queue_read])
      end

      def normalize_limit
        value = params[:limit].to_i
        value = QueueRetriever::DEFAULT_LIMIT if value <= 0
        [value, QueueRetriever::MAX_LIMIT].min
      end

      def queue_item(snapshot)
        {
          snapshot_id: snapshot.id,
          hazard_point_id: snapshot.hazard_point_id,
          name: snapshot.hazard_point&.name,
          point_type: snapshot.point_type,
          total_score: snapshot.total_score,
          risk_level: snapshot.risk_level,
          dispatch_status: snapshot.dispatch_status,
          road_status: snapshot.road_status,
          snapshot_at: snapshot.snapshot_at.iso8601,
          strategy_version: snapshot.strategy_version,
          last_inspected_at: snapshot.last_inspected_at&.iso8601
        }
      end
    end
  end
end
