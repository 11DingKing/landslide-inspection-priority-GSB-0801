module Api
  module V1
    class StrategiesController < BaseController
      def index
        strategies = ScoringStrategy.order(effective_at: :desc, version: :desc)
        render json: StrategySerializer.many(strategies)
      end

      def show
        strategy = ScoringStrategy.find(params[:id])
        render json: StrategySerializer.one(strategy)
      end

      def create
        attrs = strategy_params.merge(status: "draft")
        strategy = StrategyManager.draft(attrs)
        render json: StrategySerializer.one(strategy), status: :created
      end

      def publish
        strategy = ScoringStrategy.find(params[:id])
        published = StrategyManager.publish_draft!(strategy)
        render json: StrategySerializer.one(published)
      end

      def active
        time = params[:at].present? ? Time.iso8601(params[:at]) : Time.current
        strategy = StrategyResolver.resolve(time)
        if strategy
          render json: StrategySerializer.one(strategy)
        else
          render json: { error: "not_found",
                         message: "no published strategy effective at #{time.iso8601}" },
                 status: :not_found
        end
      rescue ArgumentError
        render json: { error: "bad_request", message: "at must be ISO8601" },
               status: :bad_request
      end

      private

      def strategy_params
        p = params.require(:strategy).permit(:name, :description, :effective_at, :version)
        rules = params[:strategy][:rules]
        if rules.present?
          p[:rules] = rules.respond_to?(:to_unsafe_h) ? rules.to_unsafe_h : rules.to_h
        end
        p[:effective_at] = Time.iso8601(p[:effective_at]) if p[:effective_at].is_a?(String)
        p.to_h
      end
    end
  end
end
