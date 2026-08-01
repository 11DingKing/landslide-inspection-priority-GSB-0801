# frozen_string_literal: true

module Api
  module V1
    # Snapshot creation is idempotent on the caller-supplied business
    # identifier (client_reference):
    #   * same identifier + same content  -> 200 with the original snapshot
    #     and its score (nothing is rewritten);
    #   * same identifier + other content -> 409 Conflict;
    #   * no identifier                   -> plain create (201).
    class EvidenceSnapshotsController < ApplicationController
      def create
        point = HazardPoint.find(params[:hazard_point_id])
        attrs = snapshot_params
        reference = attrs[:client_reference].presence

        if reference && (existing = EvidenceSnapshot.find_by(client_reference: reference))
          return render_idempotent(existing, point, attrs)
        end

        snapshot = point.evidence_snapshots.create!(attrs)
        render json: serialize(snapshot), status: :created
      rescue ActiveRecord::RecordNotUnique
        # Lost an insert race on the client_reference unique index: the winner
        # has committed by now, so resolve this as an idempotent resubmission.
        render_idempotent(EvidenceSnapshot.find_by!(client_reference: reference), point, attrs)
      rescue ActiveRecord::RecordInvalid => e
        # The model-level uniqueness validation lost the same race (the winner
        # committed between the check and the insert).
        raise e unless reference && e.record.errors[:client_reference].any?

        render_idempotent(EvidenceSnapshot.find_by!(client_reference: reference), point, attrs)
      end

      private

      def render_idempotent(existing, point, attrs)
        unless existing.hazard_point_id == point.id && existing.same_evidence?(attrs)
          return render json: { error: "client_reference '#{existing.client_reference}' already exists with different content" },
                        status: :conflict
        end

        render json: serialize(existing), status: :ok
      end

      # Fetch-or-compute the score without ever rewriting history: the
      # calculator is idempotent per (snapshot, strategy) pair.
      def score_for(snapshot)
        PriorityCalculator.call(snapshot: snapshot).explanation
      rescue PriorityCalculator::NoApplicableStrategy
        nil
      end

      def snapshot_params
        params.expect(evidence_snapshot: %i[rainfall_24h_mm historical_event_count
                                            last_inspected_at road_accessible
                                            captured_at client_reference note])
      end

      def serialize(snapshot)
        {
          "id" => snapshot.id,
          "hazard_point_id" => snapshot.hazard_point_id,
          "client_reference" => snapshot.client_reference,
          "rainfall_24h_mm" => snapshot.rainfall_24h_mm.to_s,
          "historical_event_count" => snapshot.historical_event_count,
          "last_inspected_at" => snapshot.last_inspected_at&.iso8601,
          "road_accessible" => snapshot.road_accessible,
          "captured_at" => snapshot.captured_at.iso8601,
          "note" => snapshot.note,
          "score" => score_for(snapshot)
        }
      end
    end
  end
end
