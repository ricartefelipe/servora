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
                                             { buckets: [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30] }]
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

    def register_all(registry)
      DEFINITIONS.each do |name, (type, docstring, labels, options)|
        metric_class = { counter: Prometheus::Client::Counter, histogram: Prometheus::Client::Histogram }.fetch(type)
        registry.register(metric_class.new(name, docstring:, labels:, **(options || {})))
      end
    end
  end
end
