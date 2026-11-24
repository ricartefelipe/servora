# frozen_string_literal: true

module Subscriptions
  # Charges a subscription invoice through the platform account, outside any
  # transaction, looking the charge up by reference after earlier attempts.
  class SubmitInvoiceCharge
    def initialize(organization_id:, invoice_id:)
      @organization_id = organization_id
      @invoice_id = invoice_id
    end

    def call
      invoice, customer = claim
      return unless invoice

      gateway = Payments::Gateways.for_platform
      charge = invoice.as_gateway_charge
      remote = (gateway.find_charge(charge) if invoice.attempts > 1 || invoice.charge_status == "unknown") ||
               gateway.create_charge(charge, customer)
      record(charge_status: "submitted", external_id: remote.external_id, payment_url: remote.payment_url, last_error: nil)
      if remote.status == "confirmed"
        ConfirmInvoice.new(organization_id: @organization_id, invoice_id: @invoice_id,
          paid_at: remote.paid_at).call
      end
    rescue Payments::Gateways::Errors::Rejected => e
      record(charge_status: "failed", last_error: e.message.truncate(500))
    rescue Payments::Gateways::Errors::AmbiguousResponse => e
      record(charge_status: "unknown", last_error: e.message.truncate(500))
      raise
    end

    private

    def tenant(&) = Servora::Tenancy.with_organization(@organization_id, &)

    def claim
      tenant do
        invoice = SubscriptionInvoice.lock.find_by(id: @invoice_id)
        next nil unless invoice&.status == "open" && %w[pending unknown].include?(invoice.charge_status)

        invoice.update!(attempts: invoice.attempts + 1)
        organization = Organization.find(@organization_id)
        customer = Payments::Gateways::PlatformCustomer.new(id: organization.id, document: organization.document, email: nil,
          name: organization.legal_name.presence || organization.name)
        [invoice, customer]
      end
    end

    def record(**attributes)
      tenant do
        invoice = SubscriptionInvoice.lock.find(@invoice_id)
        invoice.update!(attributes.merge(last_synced_at: Time.current)) if invoice.status == "open"
      end
    end
  end
end
