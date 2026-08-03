# frozen_string_literal: true

module Api
  module V1
    # Computes the priority of an evidence snapshot and returns the full
    # explanation: locked component scores, locked ranges, the strategy
    # version and the snapshot capture time.
    #
    # Replaying a historical snapshot is the same call: omit
    # strategy_version_id to re-derive the score under the strategy that was
    # effective at the snapshot's captured_at, or pass one explicitly for a
    # comparative replay. The unique (snapshot, strategy) index plus the
    # deterministic engine guarantee an identical, idempotent result even
    # under concurrent computation.
    class PrioritiesController < ApplicationController
      def create
        snapshot = EvidenceSnapshot.find(create_params[:evidence_snapshot_id])
        strategy = create_params[:strategy_version_id].presence &&
                   StrategyVersion.find(create_params[:strategy_version_id])

        record = PriorityCalculator.call(snapshot: snapshot, strategy_version: strategy)
        render json: record.explanation, status: :created
      end

      def explanation
        record = ScoreRecord.find(params[:id])
        render json: record.explanation
      end

      private

      def create_params
        params.expect(priority: %i[evidence_snapshot_id strategy_version_id])
      end
    end
  end
end
