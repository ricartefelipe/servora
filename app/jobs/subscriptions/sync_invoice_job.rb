# frozen_string_literal: true

module Subscriptions
  # Polling fallback for platform invoices: unknown submissions are resubmitted
  # (with lookup by reference first); submitted ones are checked for payment.
  class SyncInvoiceJob < ApplicationJob
    queue_as :integrations

    retry_on Payments::Gateways::Errors::Unavailable, Payments::Gateways::Errors::AmbiguousResponse,
      wait: :polynomially_longer, attempts: 3

    def perform(organization_id, invoice_id)
      invoice = Servora::Tenancy.with_organization(organization_id) { SubscriptionInvoice.find_by(id: invoice_id) }
      return unless invoice&.status == "open"
      return Subscriptions::SubmitInvoiceCharge.new(organization_id:, invoice_id:).call if invoice.charge_status == "unknown"

      remote = Payments::Gateways.for_platform.find_charge(invoice.as_gateway_charge)
      return unless remote&.status == "confirmed"

      Subscriptions::ConfirmInvoice.new(organization_id:, invoice_id:, paid_at: remote.paid_at).call
    end
  end
end
