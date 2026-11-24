# frozen_string_literal: true

module Servora
  # Builders of structured log lines (JSON). Correlation comes from Current
  # (request id, organization, actor) set by the controllers and jobs.
  module StructuredLog
    module_function

    def request(event, status)
      payload = event.payload
      line(
        request_id: payload[:request]&.request_id || payload.dig(:headers, "action_dispatch.request_id"),
        event: "http.request", method: payload[:method], path: payload[:path].to_s.split("?").first,
        controller: payload[:controller], action: payload[:action], status:,
        duration_ms: event.duration.round(1), db_ms: payload[:db_runtime]&.round(1), view_ms: payload[:view_runtime]&.round(1),
        exception: payload[:exception]&.first
      )
    end

    def slow_query(event, name)
      sql = event.payload[:sql].to_s.squish
      line(event: "db.slow_query", name:, duration_ms: event.duration.round(1), sql: sql.first(1000))
    end

    def line(**fields)
      context = { time: Time.current.utc.iso8601(3), request_id: Current.request_id, organization_id: Current.organization&.id,
                  actor_type: Current.actor_type }
      JSON.generate(context.merge(fields.compact).compact)
    end
  end
end
