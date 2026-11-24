# frozen_string_literal: true

module Payments
  # Polling fallback: charges awaiting payment or with an unknown submission
  # outcome are reconciled with the provider at a bounded rate.
  class ReconcileJob < ApplicationJob
    queue_as :integrations

    STALE_AFTER = 5.minutes
    BATCH = 100

    def perform
      Servora::ActiveOrganizations.each_id do |organization_id|
        due_charge_ids(organization_id).each { |charge_id| Payments::SyncChargeJob.perform_later(organization_id, charge_id) }
      end
    end

    private

    def due_charge_ids(organization_id)
      Servora::Tenancy.with_organization(organization_id) do
        PaymentCharge.where(status: %w[submitted unknown])
          .where("last_synced_at IS NULL OR last_synced_at < ?", STALE_AFTER.ago)
          .order(:last_synced_at).limit(BATCH).pluck(:id)
      end
    end
  end
end
