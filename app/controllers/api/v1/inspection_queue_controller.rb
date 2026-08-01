# frozen_string_literal: true

module Api
  module V1
    # The inspection queue. Without parameters this is the live view: every
    # hazard point appears once with its current score. Passing
    # ?snapshot=<name> pins the traversal to a previously captured queue
    # snapshot (membership and strategy round fixed at capture time), so
    # continuing with an old cursor can neither skip nor duplicate entries
    # when recomputation moves the live current pointer.
    class InspectionQueueController < ApplicationController
      def index
        snapshot = params[:snapshot].presence &&
                   QueueSnapshot.find_by!(name: params[:snapshot])

        entry = InspectionQueue.call(
          limit: params[:limit] || InspectionQueue::DEFAULT_LIMIT,
          cursor: params[:cursor],
          scheduling_status: params[:scheduling_status].presence,
          snapshot: snapshot
        )

        render json: {
          "snapshot" => snapshot && {
            "name" => snapshot.name,
            "strategy_version" => snapshot.strategy_version.version
          },
          "entries" => entry.records.map { |r| serialize(r) },
          "next_cursor" => entry.next_cursor
        }
      end

      private

      def serialize(record)
        {
          "score_record_id" => record.id,
          "hazard_point" => {
            "id" => record.hazard_point.id,
            "external_code" => record.hazard_point.external_code,
            "name" => record.hazard_point.name,
            "kind" => record.hazard_point.kind
          },
          "evidence_snapshot_id" => record.evidence_snapshot_id,
          "snapshot_captured_at" => record.evidence_snapshot.captured_at.iso8601,
          "strategy_version" => record.strategy_version.version,
          "total_score" => record.total_score,
          "risk_level" => record.risk_level,
          "scheduling_status" => record.scheduling_status,
          "components" => record.components,
          "computed_at" => record.computed_at.iso8601
        }
      end
    end
  end
end
