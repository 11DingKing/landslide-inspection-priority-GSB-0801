# frozen_string_literal: true

module Api
  module V1
    class StrategyVersionsController < ApplicationController
      def index
        versions = StrategyVersion.order(:version).limit(200)
        render json: versions.map { |v| serialize(v) }
      end

      # Creates a draft. Pass publish: true to publish immediately; an
      # overlapping published range is rejected with 409 Conflict.
      def create
        version = StrategyVersion.create!(
          version: create_params[:version],
          rules: rules_payload,
          effective_range: StrategyVersion.compose_range(
            Time.zone.parse(create_params[:effective_from].to_s),
            create_params[:effective_to].present? ? Time.zone.parse(create_params[:effective_to].to_s) : nil
          )
        )
        version.publish! if ActiveModel::Type::Boolean.new.cast(params[:publish])
        render json: serialize(version), status: :created
      end

      def publish
        version = StrategyVersion.find(params[:id])
        version.publish!
        render json: serialize(version)
      end

      def retire
        version = StrategyVersion.find(params[:id])
        version.retire!
        render json: serialize(version)
      end

      private

      def create_params
        params.expect(strategy_version: %i[version effective_from effective_to])
      end

      # rules is arbitrary JSON; its shape is validated against the locked
      # component schema by Scoring::Engine.validate_rules!, not by strong
      # parameters.
      def rules_payload
        raw = params.dig(:strategy_version, :rules)
        raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      end

      def serialize(version)
        {
          "id" => version.id,
          "version" => version.version,
          "status" => version.status,
          "effective_from" => version.effective_from&.iso8601,
          "effective_to" => version.effective_to&.iso8601,
          "published_at" => version.published_at&.iso8601,
          "rules" => version.rules
        }
      end
    end
  end
end
