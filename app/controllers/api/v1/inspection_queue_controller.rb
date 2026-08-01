# frozen_string_literal: true

module Api
  module V1
    # The inspection queue: every hazard point appears once with its current
    # score, ordered by (total_score DESC, id ASC) with keyset pagination.
    # Blocked points keep their original risk level and are merely flagged —
    # pass scheduling_status=schedulable to hide them from a patrol plan.
    class InspectionQueueController < ApplicationController
      def index
        entry = InspectionQueue.call(
          limit: params[:limit] || InspectionQueue::DEFAULT_LIMIT,
          cursor: params[:cursor],
          scheduling_status: params[:scheduling_status].presence
        )

        render json: {
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
