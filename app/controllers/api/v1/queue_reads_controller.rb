module Api
  module V1
    class QueueReadsController < BaseController
      def create
        at = parse_time(params[:at]) || Time.current
        queue_read = QueueReadManager.create(
          business_id: params.require(:business_id),
          at: at,
          dispatch_status: params[:dispatch_status],
          include_blocked: params[:include_blocked] != "false"
        )
        render json: QueueReadSerializer.one(queue_read), status: :created
      end

      def show
        queue_read = QueueRead.find_by!(business_id: params[:business_id])
        render json: QueueReadSerializer.one(queue_read)
      end

      private

      def parse_time(value)
        return if value.blank?

        Time.iso8601(value)
      rescue ArgumentError
        raise ActionController::ParameterMissing, "at must be an ISO8601 timestamp"
      end
    end
  end
end
