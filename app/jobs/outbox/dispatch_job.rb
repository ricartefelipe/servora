# frozen_string_literal: true

module Outbox
  # Drains due outbox events in batches for a bounded amount of time. Runs on a
  # recurring schedule (config/recurring.yml) and after commits (Outbox::Kick).
  # Several instances may run at once: claiming uses SKIP LOCKED.
  class DispatchJob < ApplicationJob
    queue_as :outbox

    TIME_BUDGET = 20.seconds

    def perform
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIME_BUDGET
      dispatcher = Outbox::Dispatcher.new
      loop do
        stats = dispatcher.run_once
        break if stats.claimed < Outbox::Dispatcher::DEFAULT_BATCH
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      end
    end
  end
end
