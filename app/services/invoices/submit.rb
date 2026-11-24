# frozen_string_literal: true

module Invoices
  # Issues a pending invoice at the provider, outside any transaction. After
  # an earlier attempt (or an unknown outcome) the invoice is first looked up
  # by external reference, so a lost response never produces a second NFS-e.
  class Submit
    def initialize(organization_id:, invoice_id:)
      @organization_id = organization_id
      @invoice_id = invoice_id
    end

    def call
      invoice, context = claim
      return unless invoice

      gateway = Payments::Gateways.for(context[:integration])
      found = gateway.find_invoice(invoice) if invoice.attempts > 1 || invoice.status == "unknown"
      Apply.new(organization_id: @organization_id, invoice_id: @invoice_id)
        .call(found || gateway.issue_invoice(invoice, context[:customer], context[:settings], context[:charge]))
    rescue Payments::Gateways::Errors::Rejected => e
      Apply.new(organization_id: @organization_id, invoice_id: @invoice_id).fail(e.message)
    rescue Payments::Gateways::Errors::AmbiguousResponse => e
      Apply.new(organization_id: @organization_id, invoice_id: @invoice_id).unknown(e.message)
      raise
    end

    private

    def claim
      Servora::Tenancy.with_organization(@organization_id) do
        invoice = ServiceInvoice.lock.find_by(id: @invoice_id)
        next nil unless invoice && %w[pending unknown].include?(invoice.status)

        invoice.update!(attempts: invoice.attempts + 1)
        receivable = Receivable.find(invoice.receivable_id)
        [invoice, { integration: PaymentIntegration.for(@organization_id), customer: Customer.find(receivable.customer_id),
                    settings: FiscalSetting.for(@organization_id), charge: settled_charge(receivable) }]
      end
    end

    def settled_charge(receivable)
      PaymentCharge.where(receivable_id: receivable.id, status: "confirmed").where.not(external_id: nil).order(:confirmed_at).last
    end
  end
end
