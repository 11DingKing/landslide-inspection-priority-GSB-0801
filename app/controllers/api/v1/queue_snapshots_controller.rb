# frozen_string_literal: true

module Api
  module V1
    # Creates and inspects named queue read snapshots. Creation is
    # idempotent on the name: re-capturing "queue-20260802-01" returns the
    # original snapshot (200) instead of duplicating it.
    class QueueSnapshotsController < ApplicationController
      def index
        snapshots = QueueSnapshot.order(:id).limit(200)
        render json: snapshots.map { |s| serialize(s) }
      end

      def show
        render json: serialize(find_snapshot)
      end

      def create
        name = create_params[:name]
        existing = QueueSnapshot.find_by(name: name)
        return render json: serialize(existing), status: :ok if existing

        snapshot = QueueSnapshot.capture!(name: name, at: capture_time)
        render json: serialize(snapshot), status: :created
      rescue ActiveRecord::RecordNotUnique
        # Lost a concurrent capture race on the same name; adopt the winner.
        render json: serialize(QueueSnapshot.find_by!(name: name)), status: :ok
      end

      private

      def find_snapshot
        QueueSnapshot.find_by!(name: params[:id])
      end

      def create_params
        params.expect(queue_snapshot: %i[name at])
      end

      # Optional explicit capture time; the pinned strategy round is the
      # published version applicable at that moment.
      def capture_time
        create_params[:at].present? ? Time.zone.parse(create_params[:at]) : Time.current
      end

      def serialize(snapshot)
        {
          "id" => snapshot.id,
          "name" => snapshot.name,
          "strategy_version" => snapshot.strategy_version.version,
          "strategy_round_pinned_at" => snapshot.created_at.iso8601,
          "entry_count" => snapshot.entry_count
        }
      end
    end
  end
end
