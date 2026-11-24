# frozen_string_literal: true

require "prometheus/client"

module Servora
  # Prometheus metrics with low-cardinality labels only (never organization,
  # customer or order identifiers). Definitions live here so every metric name,
  # type and label set is reviewed in one place.
  module Metrics
    DEFINITIONS = {
      http_request_duration_seconds: [:histogram, "Duração das requisições HTTP", %i[controller action status_class],
                                      { buckets: [0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10] }],
      http_requests_errors_total: [:counter, "Requisições com status 5xx", %i[controller action]],
      db_slow_queries_total: [:counter, "Consultas acima do limite configurado", %i[name]],
      jobs_total: [:counter, "Jobs executados por resultado", %i[job outcome]],
      job_duration_seconds: [:histogram, "Duração dos jobs", %i[job], { buckets: [0.05, 0.1, 0.5, 1, 5, 15, 60, 300] }],
      outbox_events_processed_total: [:counter, "Eventos da outbox por resultado", %i[event_type outcome]],
      outbox_kick_failures_total: [:counter, "Falhas ao acionar o despachante após commit", []],
      schedule_conflicts_total: [:counter, "Reservas de agenda recusadas por conflito", %i[source]],
      integration_requests_total: [:counter, "Chamadas a integrações externas", %i[integration operation outcome]],
      integration_request_duration_seconds: [:histogram, "Duração das chamadas externas", %i[integration operation],
                                             { buckets: [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30] }],
      webhook_deliveries_total: [:counter, "Entregas de webhooks por resultado", %i[outcome]],
      outbox_events: [:gauge, "Eventos da outbox por situação", %i[status], { store_settings: { aggregation: :most_recent } }],
      outbox_oldest_pending_seconds: [:gauge, "Idade do evento pendente mais antigo da outbox", [],
                                      { store_settings: { aggregation: :most_recent } }],
      jobs_ready: [:gauge, "Jobs prontos aguardando execução por fila", %i[queue],
                   { store_settings: { aggregation: :most_recent } }],
      jobs_failed: [:gauge, "Jobs com falha definitiva registrada", [], { store_settings: { aggregation: :most_recent } }]
    }.freeze

    module_function

    def registry
      @registry ||= Prometheus::Client::Registry.new.tap { |registry| register_all(registry) }
    end

    def increment(name, labels = {}, by: 1)
      registry.get(name).increment(by:, labels:)
    end

    def observe(name, value, labels = {})
      registry.get(name).observe(value, labels:)
    end

    def set(name, value, labels = {})
      registry.get(name).set(value, labels:)
    end

    # Measures an external call: duration and outcome (ok / error class name).
    def measure_integration(integration, operation)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = "error"
      result = yield
      outcome = "ok"
      result
    rescue StandardError => e
      outcome = e.class.name.demodulize.underscore
      raise
    ensure
      observe(:integration_request_duration_seconds, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        { integration:, operation: })
      increment(:integration_requests_total, { integration:, operation:, outcome: })
    end

    # Gauge aggregation only applies to the multi-process file store.
    def store_options(options)
      return options if Prometheus::Client.config.data_store.class.name.end_with?("DirectFileStore")

      options.except(:store_settings)
    end

    def register_all(registry)
      DEFINITIONS.each do |name, (type, docstring, labels, options)|
        metric_class = { counter: Prometheus::Client::Counter, histogram: Prometheus::Client::Histogram,
                         gauge: Prometheus::Client::Gauge }.fetch(type)
        registry.register(metric_class.new(name, docstring:, labels:, **store_options(options || {})))
      end
    end
  end
end
