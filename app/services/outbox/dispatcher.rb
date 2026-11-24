# frozen_string_literal: true

module Outbox
  # Claims due events and processes each one inside its organization context.
  #
  #   1. claim          servora_claim_outbox_events (lease, SKIP LOCKED)
  #   2. handle         tenant transaction: lease check + idempotent handlers
  #   3. enqueue jobs   outside any transaction
  #   4. acknowledge    tenant transaction: mark processed if the lease is still ours
  #
  # A failure records history and either schedules a retry or sets the event
  # aside as "dead" (manual, authorized reprocessing).
  class Dispatcher
    Stats = Struct.new(:claimed, :processed, :retried, :dead, :skipped) do
      def self.zero = new(0, 0, 0, 0, 0)
    end

    DEFAULT_BATCH = 50
    DEFAULT_LEASE = 120

    attr_reader :worker_id

    def initialize(worker_id: self.class.default_worker_id, batch_size: DEFAULT_BATCH, lease_seconds: DEFAULT_LEASE,
                   clock: -> { Time.current })
      @worker_id = worker_id
      @batch_size = batch_size
      @lease_seconds = lease_seconds
      @clock = clock
    end

    def self.default_worker_id
      "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}"
    end

    def run_once
      stats = Stats.zero
      claim.each do |event_id, organization_id|
        stats.claimed += 1
        outcome = process(event_id, organization_id)
        stats[outcome] += 1
      end
      stats
    end

    def claim
      ActiveRecord::Base.connection.select_rows(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT event_id, organization_id FROM servora_claim_outbox_events(?, ?, ?)", @worker_id, @batch_size, @lease_seconds]
        )
      )
    end

    def process(event_id, organization_id)
      Processing.new(event_id:, organization_id:, worker_id: @worker_id, clock: @clock).call
    end
  end
end
