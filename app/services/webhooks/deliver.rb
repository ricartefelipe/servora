# frozen_string_literal: true

require "net/http"

module Webhooks
  # Sends one delivery. The HTTP call happens outside any transaction, to the
  # address validated by SafeUrl (pinned: no second DNS resolution), without
  # following redirects. Receivers verify:
  #
  #   Servora-Signature: t=<unix time>,v1=<hex HMAC-SHA256(secret, "<t>.<body>")>
  #
  # and deduplicate by Servora-Event-Id (stable across retries).
  class Deliver
    MAX_ATTEMPTS = 8
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class Retry < Servora::TransientError; end

    def initialize(organization_id:, delivery_id:)
      @organization_id = organization_id
      @delivery_id = delivery_id
    end

    def call
      delivery, url, secret = claim
      return unless delivery

      code, error = post(url, secret, delivery)
      record(code, error)
    end

    def self.signature(secret, timestamp, body) = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")

    # delivered on 2xx; failed when the URL is refused or attempts are
    # exhausted; pending (to be retried) otherwise.
    def self.outcome(code, error, attempts)
      return "delivered" if code&.between?(200, 299)
      return "failed" if error&.start_with?("URL recusada") || attempts >= MAX_ATTEMPTS

      "pending"
    end

    private

    def tenant(&) = Servora::Tenancy.with_organization(@organization_id, &)

    def claim
      tenant do
        delivery = WebhookDelivery.lock.find_by(id: @delivery_id)
        next nil unless delivery&.status == "pending"

        endpoint = WebhookEndpoint.find(delivery.webhook_endpoint_id)
        delivery.update!(attempts: delivery.attempts + 1, last_attempt_at: Time.current)
        [delivery, endpoint.url, endpoint.secret]
      end
    end

    def post(url, secret, delivery)
      target = SafeUrl.check!(url)
      body = JSON.generate(delivery.payload)
      response = http(target).request(build_request(target.uri, body, secret, delivery))
      [response.code.to_i, nil]
    rescue SafeUrl::Unsafe => e
      [nil, "URL recusada: #{e.message}"]
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      [nil, e.class.name]
    end

    def http(target)
      Net::HTTP.new(target.uri.host, target.uri.port).tap do |http|
        http.ipaddr = target.address
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = READ_TIMEOUT
      end
    end

    def build_request(uri, body, secret, delivery)
      timestamp = Time.current.to_i
      Net::HTTP::Post.new(uri.request_uri).tap do |request|
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Servora-Webhooks"
        request["Servora-Event-Id"] = delivery.event_id
        request["Servora-Event-Type"] = delivery.event_type
        request["Servora-Signature"] = "t=#{timestamp},v1=#{self.class.signature(secret, timestamp, body)}"
        request.body = body
      end
    end

    def record(code, error)
      outcome = tenant do
        delivery = WebhookDelivery.lock.find(@delivery_id)
        status = self.class.outcome(code, error, delivery.attempts)
        delivery.update!(status:, last_response_code: code, last_error: status == "delivered" ? nil : (error || "HTTP #{code}"),
          delivered_at: status == "delivered" ? Time.current : nil)
        status
      end
      raise Retry, "webhook delivery #{@delivery_id} will be retried" if outcome == "pending"
    end
  end
end
