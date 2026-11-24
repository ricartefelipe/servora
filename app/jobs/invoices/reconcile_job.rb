# frozen_string_literal: true

module Invoices
  # Periodic follow-up of invoices still in processing, unknown or canceling.
  class ReconcileJob < ApplicationJob
    queue_as :integrations

    def perform
      Servora::ActiveOrganizations.each_id do |organization_id|
        ids = Servora::Tenancy.with_organization(organization_id) do
          ServiceInvoice.where(status: %w[scheduled unknown canceling])
            .where("last_synced_at IS NULL OR last_synced_at < ?", 5.minutes.ago).order(:last_synced_at).limit(100).pluck(:id)
        end
        ids.each { |invoice_id| Invoices::SyncJob.perform_later(organization_id, invoice_id) }
      end
    end
  end
end
