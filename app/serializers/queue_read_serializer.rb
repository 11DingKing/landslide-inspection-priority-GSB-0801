class QueueReadSerializer
  def self.one(queue_read)
    {
      id: queue_read.id,
      business_id: queue_read.business_id,
      strategy_version: queue_read.strategy_version,
      cutoff_at: queue_read.cutoff_at.iso8601,
      dispatch_status: queue_read.dispatch_status,
      created_at: queue_read.created_at.iso8601
    }
  end
end
