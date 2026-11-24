# frozen_string_literal: true

module Subscriptions
  # Daily platform billing for every organization (one subscription per
  # transaction; failures of one organization do not stop the others).
  class BillingJob < ApplicationJob
    queue_as :default

    def perform
      Servora::ActiveOrganizations.each_id do |organization_id|
        Servora::Tenancy.with_organization(organization_id) do
          subscription = Subscription.includes(:plan).find_by(organization_id:)
          Subscriptions::Bill.new(subscription:).call if subscription
        end
      rescue ActiveRecord::ActiveRecordError, Servora::RuleViolation => e
        Rails.logger.warn(Servora::StructuredLog.line(event: "subscriptions.billing_failed", organization_id:,
          error_class: e.class.name))
      end
      reconcile
    end

    private

    def reconcile
      Servora::ActiveOrganizations.each_id do |organization_id|
        ids = Servora::Tenancy.with_organization(organization_id) do
          SubscriptionInvoice.open_invoices.where(charge_status: %w[submitted unknown]).pluck(:id)
        end
        ids.each { |invoice_id| Subscriptions::SyncInvoiceJob.perform_later(organization_id, invoice_id) }
      end
    end
  end
end
