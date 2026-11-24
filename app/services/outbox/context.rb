# frozen_string_literal: true

module Outbox
  # Collects side effects requested by handlers. Jobs are enqueued by the
  # dispatcher only after the handler transaction commits and before the event
  # is marked as processed (at-least-once; jobs must be idempotent).
  class Context
    attr_reader :jobs

    def initialize
      @jobs = []
    end

    def enqueue(job_class, *arguments)
      @jobs << [job_class, arguments]
    end
  end
end
