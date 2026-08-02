class QueueReadManager
  class Error < StandardError; end

  def self.create(business_id:, at: Time.current, dispatch_status: nil,
                  include_blocked: true)
    existing = QueueRead.find_by(business_id: business_id)
    return existing if existing

    time = at.respond_to?(:to_time) ? at.to_time.utc : Time.current.utc
    strategy = StrategyResolver.resolve!(time)

    status = normalize_dispatch(dispatch_status, include_blocked)

    QueueRead.create!(
      business_id: business_id,
      strategy_version: strategy.version,
      cutoff_at: time,
      dispatch_status: status
    )
  rescue ActiveRecord::RecordNotUnique
    QueueRead.find_by!(business_id: business_id)
  end

  def self.find_by_business_id(business_id)
    QueueRead.find_by!(business_id: business_id)
  end

  def self.normalize_dispatch(dispatch_status, include_blocked)
    return dispatch_status if dispatch_status.present?

    include_blocked ? nil : "schedulable"
  end
end
