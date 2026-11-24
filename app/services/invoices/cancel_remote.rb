# frozen_string_literal: true

module Invoices
  class CancelRemote
    def initialize(organization_id:, invoice_id:)
      @organization_id = organization_id
      @invoice_id = invoice_id
    end

    def call
      invoice, integration = Servora::Tenancy.with_organization(@organization_id) do
        found = ServiceInvoice.find_by(id: @invoice_id)
        next nil unless found&.status == "canceling"

        [found, PaymentIntegration.for(@organization_id)]
      end
      return unless invoice

      Apply.new(organization_id: @organization_id, invoice_id: @invoice_id)
        .call(Payments::Gateways.for(integration).cancel_invoice(invoice))
    end
  end
end
