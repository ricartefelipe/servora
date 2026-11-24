# frozen_string_literal: true

module Outbox
  # Best-effort, low-latency trigger of the dispatcher after a commit. Failing
  # here never loses an event: the recurring dispatcher (config/recurring.yml)
  # processes everything that is due.
  module Kick
    module_function

    def call
      Outbox::DispatchJob.perform_later
    rescue ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError => e
      Rails.logger.warn(Servora::StructuredLog.line(event: "outbox.kick_failed", error_class: e.class.name))
      Servora::Metrics.increment(:outbox_kick_failures_total)
      nil
    end
  end
end
