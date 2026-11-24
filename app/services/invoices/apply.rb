# frozen_string_literal: true

module Invoices
  # Records what the provider reported about an invoice (short transaction,
  # row lock). A canceled invoice frees the receivable for a new one.
  class Apply
    def initialize(organization_id:, invoice_id:)
      @organization_id = organization_id
      @invoice_id = invoice_id
    end

    def call(remote)
      update(status: remote.status, external_id: remote.external_id, number: remote.number || :keep,
        verification_code: remote.verification_code || :keep, pdf_url: remote.pdf_url || :keep, xml_url: remote.xml_url || :keep,
        last_error: (remote.message if remote.status == "error"), issued_at: (Time.current if remote.status == "authorized"))
    end

    def fail(message) = update(status: "error", last_error: message.truncate(500))
    def unknown(message) = update(status: "unknown", last_error: message.truncate(500))

    private

    def update(**changes)
      Servora::Tenancy.with_organization(@organization_id) do
        invoice = ServiceInvoice.lock.find(@invoice_id)
        attributes = changes.reject { |_, value| value == :keep }.merge(last_synced_at: Time.current)
        attributes[:issued_at] = invoice.issued_at || attributes[:issued_at]
        previous = invoice.status
        invoice.update!(attributes)
        if previous != invoice.status
          AuditEvent.record!(action: "service_invoice.#{invoice.status}", auditable: invoice,
            organization: Organization.find(@organization_id),
            changes: { number: invoice.number, error: invoice.last_error }.compact)
        end
        invoice
      end
    end
  end
end
