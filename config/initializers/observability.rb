# Request metrics, slow query detection and one structured log line per
# request (with the correlation id), from Active Support notifications.
#
# Metric labels are low-cardinality (controller, action, status class). Log
# lines may carry identifiers (request, organization, user) but never request
# parameters, which may contain personal data.

if (directory = ENV["PROMETHEUS_DATA_DIR"].presence)
  # Several Puma processes: aggregate metrics through files in a shared directory.
  require "prometheus/client/data_stores/direct_file_store"
  FileUtils.mkdir_p(directory)
  Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: directory)
end

Rails.application.config.after_initialize do
  slow_query_ms = Integer(ENV.fetch("SLOW_QUERY_MS", "500"))

  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |event|
    payload = event.payload
    status = payload[:status] || (payload[:exception] ? 500 : 0)
    labels = { controller: payload[:controller].to_s, action: payload[:action].to_s, status_class: "#{status / 100}xx" }
    Servora::Metrics.observe(:http_request_duration_seconds, event.duration / 1000.0, labels)
    Servora::Metrics.increment(:http_requests_errors_total, labels.except(:status_class)) if status >= 500

    Rails.logger.info(Servora::StructuredLog.request(event, status))
  end

  ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
    next if event.duration < slow_query_ms || event.payload[:name].in?(%w[SCHEMA TRANSACTION])

    name = event.payload[:name].presence || "SQL"
    Servora::Metrics.increment(:db_slow_queries_total, { name: name.split.first(2).join(" ") })
    Rails.logger.warn(Servora::StructuredLog.slow_query(event, name))
  end
end
