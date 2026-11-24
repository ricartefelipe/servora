# frozen_string_literal: true

module Webhooks
  # Payment notifications of the platform's own Asaas account (subscription
  # invoices). Authenticated by PLATFORM_ASAAS_WEBHOOK_TOKEN; the invoice
  # reference carries the organization id, which selects the tenant context.
  # The notification is stored before the 200 response and deduplicated.
  class PlatformAsaasController < ActionController::API
    REFERENCE = /\Aplat-(\h{8}-\h{4}-\h{4}-\h{4}-\h{12})-/

    rate_limit to: 600, within: 1.minute

    def create
      token = ENV["PLATFORM_ASAAS_WEBHOOK_TOKEN"].to_s
      provided = request.headers["asaas-access-token"].to_s
      return head(:unauthorized) if token.empty? || !ActiveSupport::SecurityUtils.secure_compare(provided, token)

      payload = JSON.parse(request.raw_post)
      organization_id = payload.is_a?(Hash) && payload.dig("payment", "externalReference").to_s[REFERENCE, 1]
      return head(:ok) unless organization_id # not a subscription invoice: acknowledged and ignored

      Webhooks::ReceivePaymentNotification.new(organization_id:, payload:, provider: "asaas_platform").call
      head :ok
    rescue JSON::ParserError, ArgumentError
      head :bad_request
    end
  end
end
