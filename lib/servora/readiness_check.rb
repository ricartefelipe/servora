# frozen_string_literal: true

module Servora
  # Verifies that each configured database answers within a short timeout.
  # Error details are reduced to the exception class to avoid leaking
  # connection strings or hostnames through a public endpoint.
  class ReadinessCheck
    def initialize(timeout_ms:, base_class: ActiveRecord::Base)
      @timeout_ms = Integer(timeout_ms)
      @base_class = base_class
    end

    def call
      checks = { "primary" => check_connection(@base_class) { |c| ensure_migrated!(c) } }
      secondary_models.each { |name, model| checks[name] = check_connection(model) }
      checks
    end

    private

    def secondary_models
      models = {}
      models["queue"] = SolidQueue::Record if solid_queue_database?
      models["cache"] = SolidCache::Record if solid_cache_database?
      models
    end

    def check_connection(model)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute("SET LOCAL statement_timeout = #{@timeout_ms}")
          connection.select_value("SELECT 1")
        end
        yield connection if block_given?
      end
      { ok: true, latency_ms: elapsed_ms(started) }
    rescue StandardError => e
      { ok: false, error: e.class.name, latency_ms: elapsed_ms(started) }
    end

    def ensure_migrated!(connection)
      raise ActiveRecord::PendingMigrationError if connection.pool.migration_context.needs_migration?
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
    end

    def solid_queue_database?
      defined?(SolidQueue::Record) && Rails.application.config.active_job.queue_adapter == :solid_queue
    end

    def solid_cache_database?
      defined?(SolidCache::Record) && Rails.cache.is_a?(SolidCache::Store)
    end
  end
end
