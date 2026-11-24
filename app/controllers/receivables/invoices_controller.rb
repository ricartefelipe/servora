# frozen_string_literal: true

module Receivables
  # NFS-e of a receivable: request, follow-up and cancellation. Provider
  # calls run in background jobs.
  class InvoicesController < BaseController
    def create
      authorize @receivable, :invoice?
      Invoices::Request.new(receivable: @receivable, actor: current_membership).call
      back("Nota fiscal solicitada. A emissão ocorre em segundo plano.")
    end

    def sync
      authorize @receivable, :invoice?
      Invoices::SyncJob.perform_later(@receivable.organization_id, load_invoice.id)
      back("Consulta da nota solicitada.")
    end

    def cancel
      authorize @receivable, :invoice?
      Invoices::Cancel.new(invoice: load_invoice, reason: params.expect(cancellation: [:reason])[:reason],
        actor: current_membership).call
      back("Cancelamento da nota solicitado.")
    end

    private

    def load_invoice = tenant_relation(ServiceInvoice).where(receivable_id: @receivable.id).find(params.expect(:id))
  end
end
