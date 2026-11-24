# frozen_string_literal: true

module Webhooks
  # Payment notifications from Asaas. Authenticated by the per-organization
  # token Asaas sends in "asaas-access-token" (stored as a digest). The
  # notification is persisted before the 200 response; duplicates are
  # acknowledged without being stored again.
  class AsaasController < ActionController::API
    rate_limit to: 600, within: 1.minute

    def create
      organization_id = PaymentIntegration.organization_for_webhook(request.headers["asaas-access-token"])
      return head(:unauthorized) unless organization_id

      payload = JSON.parse(request.raw_post)
      raise JSON::ParserError, "payload must be an object" unless payload.is_a?(Hash)

      Webhooks::ReceivePaymentNotification.new(organization_id:, payload:).call
      head :ok
    rescue JSON::ParserError, ArgumentError
      head :bad_request
    end
  end
end
