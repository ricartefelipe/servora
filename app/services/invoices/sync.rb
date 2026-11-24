# frozen_string_literal: true

module Invoices
  # Polls the provider for invoices still being processed by the city hall,
  # with an unknown submission outcome, or being canceled.
  class Sync
    def initialize(organization_id:, invoice_id:)
      @organization_id = organization_id
      @invoice_id = invoice_id
    end

    def call
      invoice, integration = Servora::Tenancy.with_organization(@organization_id) do
        found = ServiceInvoice.find_by(id: @invoice_id)
        next nil unless found && %w[scheduled unknown canceling].include?(found.status)

        [found, PaymentIntegration.for(@organization_id)]
      end
      return unless invoice
      return Submit.new(organization_id: @organization_id, invoice_id: @invoice_id).call if invoice.status == "unknown"

      remote = Payments::Gateways.for(integration).find_invoice(invoice)
      Apply.new(organization_id: @organization_id, invoice_id: @invoice_id).call(remote) if remote
    end
  end
end
