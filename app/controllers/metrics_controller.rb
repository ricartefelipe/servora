# frozen_string_literal: true

require "prometheus/client/formats/text"

# Prometheus scrape endpoint, protected by METRICS_TOKEN (Bearer). Without a
# configured token the endpoint does not exist (404).
class MetricsController < ActionController::API
  def show
    token = ENV["METRICS_TOKEN"].to_s
    return head(:not_found) if token.empty?

    provided = request.authorization.to_s.delete_prefix("Bearer ")
    return head(:unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(provided, token)

    Servora::MetricsSnapshot.refresh!
    render plain: Prometheus::Client::Formats::Text.marshal(Servora::Metrics.registry),
      content_type: Prometheus::Client::Formats::Text::CONTENT_TYPE
  end
end
