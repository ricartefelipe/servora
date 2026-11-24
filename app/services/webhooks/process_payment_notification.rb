# frozen_string_literal: true

module Webhooks
  # Applies a stored provider notification. Payment confirmations go through
  # Payments::ConfirmCharge (idempotent); other events are kept as ignored.
  class ProcessPaymentNotification
    CONFIRMATIONS = %w[PAYMENT_RECEIVED PAYMENT_CONFIRMED PAYMENT_RECEIVED_IN_CASH].freeze

    def initialize(organization_id:, inbound_webhook_id:)
      @organization_id = organization_id
      @inbound_webhook_id = inbound_webhook_id
    end

    def call
      notification = Servora::Tenancy.with_organization(@organization_id) { InboundWebhook.find(@inbound_webhook_id) }
      return if %w[processed ignored].include?(notification.status)

      return settle_platform_invoice(notification) if notification.provider == "asaas_platform"

      charge_id = confirmable_charge_id(notification)
      if charge_id
        paid_at = notification.payload.dig("payment", "paymentDate").presence&.then { |date| Time.zone.parse(date) }
        Payments::ConfirmCharge.new(organization_id: @organization_id, charge_id:, paid_at:).call
      end
      finish(charge_id ? "processed" : "ignored")
    end

    private

    def confirmable_charge_id(notification)
      return nil unless CONFIRMATIONS.include?(notification.event_type)

      reference = notification.payload.dig("payment", "externalReference")
      Servora::Tenancy.with_organization(@organization_id) { PaymentCharge.find_by(external_reference: reference)&.id }
    end

    # Subscription invoices of the platform account (confirmations only).
    def settle_platform_invoice(notification)
      reference = notification.payload.dig("payment", "externalReference")
      invoice_id = CONFIRMATIONS.include?(notification.event_type) &&
                   Servora::Tenancy.with_organization(@organization_id) { SubscriptionInvoice.find_by(external_reference: reference)&.id }
      if invoice_id
        paid_at = notification.payload.dig("payment", "paymentDate").presence&.then { |date| Time.zone.parse(date) }
        Subscriptions::ConfirmInvoice.new(organization_id: @organization_id, invoice_id:, paid_at:).call
      end
      finish(invoice_id ? "processed" : "ignored")
    end

    def finish(status)
      Servora::Tenancy.with_organization(@organization_id) do
        InboundWebhook.where(id: @inbound_webhook_id).update_all(status:, processed_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- status bookkeeping
      end
    end
  end
end
