# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Observability" do
  around do |example|
    previous = ENV.fetch("METRICS_TOKEN", nil)
    ENV["METRICS_TOKEN"] = "token-de-metricas"
    example.run
  ensure
    ENV["METRICS_TOKEN"] = previous
  end

  it "exposes Prometheus metrics only with the token" do
    get metrics_path
    expect(response).to have_http_status(:unauthorized)

    get metrics_path, headers: { "Authorization" => "Bearer token-de-metricas" }

    expect(response.content_type).to start_with("text/plain")
    expect(response.body).to include("http_request_duration_seconds", "outbox_events", "outbox_oldest_pending_seconds",
      "db_slow_queries_total", "integration_requests_total")
  end

  it "does not exist without a configured token" do
    ENV["METRICS_TOKEN"] = ""

    get metrics_path

    expect(response).to have_http_status(:not_found)
  end

  it "logs one structured line per request with the correlation id and without parameters" do
    lines = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, message = nil, &block|
      lines << message if message.is_a?(String) && message.start_with?("{")
      original.call(message, &block)
    end

    get "/up", params: { senha: "segredo" }, headers: { "X-Request-Id" => "req-observabilidade-1" }

    entry = lines.map { |line| JSON.parse(line) }.find { |line| line["event"] == "http.request" }
    expect(entry).to include("request_id" => "req-observabilidade-1", "path" => "/up", "status" => 200,
      "controller" => "HealthController")
    expect(lines.join).not_to include("segredo")
  end

  it "counts and logs slow queries without bind values" do
    counter = Servora::Metrics.registry.get(:db_slow_queries_total)
    before = counter.get(labels: { name: "Customer Load" })
    start = Time.current
    event = ActiveSupport::Notifications::Event.new("sql.active_record", start, start + 2, SecureRandom.hex(4),
      { sql: 'SELECT "customers".* FROM "customers" WHERE "customers"."id" = $1', name: "Customer Load" })

    allow(Rails.logger).to receive(:warn)
    ActiveSupport::Notifications.publish_event(event)

    expect(counter.get(labels: { name: "Customer Load" })).to eq(before + 1)
    expect(Rails.logger).to have_received(:warn).with(a_string_including('"event":"db.slow_query"', "$1"))
  end
end
