# frozen_string_literal: true

module Servora
  # Gauges refreshed at scrape time from the databases: outbox backlog (via a
  # SECURITY DEFINER aggregate, no tenant rows exposed) and Solid Queue depth.
  module MetricsSnapshot
    module_function

    def refresh!
      outbox
      queue
    end

    def outbox
      rows = ActiveRecord::Base.connection.select_rows("SELECT status, total, oldest_available_at FROM servora_outbox_backlog()")
      %w[pending processing dead].each { |status| Metrics.set(:outbox_events, 0, { status: }) }
      oldest = nil
      rows.each do |status, total, oldest_at|
        Metrics.set(:outbox_events, total.to_i, { status: })
        oldest = Time.zone.parse(oldest_at.to_s) if status == "pending" && oldest_at
      end
      Metrics.set(:outbox_oldest_pending_seconds, oldest ? [Time.current - oldest, 0].max.round : 0)
    end

    def queue
      return unless defined?(SolidQueue::ReadyExecution) && SolidQueue::ReadyExecution.table_exists?

      SolidQueue::ReadyExecution.group(:queue_name).count.each { |queue, total| Metrics.set(:jobs_ready, total, { queue: }) }
      Metrics.set(:jobs_failed, SolidQueue::FailedExecution.count)
    rescue ActiveRecord::ActiveRecordError
      nil
    end
  end
end
