# frozen_string_literal: true

module Subscriptions
  # Marks a subscription invoice as paid (idempotent) and reactivates a
  # past_due subscription once no delinquent invoice remains.
  class ConfirmInvoice
    def initialize(organization_id:, invoice_id:, paid_at: nil, actor: nil)
      @organization_id = organization_id
      @invoice_id = invoice_id
      @paid_at = paid_at
      @actor = actor
    end

    def call
      Servora::Tenancy.with_organization(@organization_id) do
        invoice = SubscriptionInvoice.lock.find(@invoice_id)
        next invoice unless invoice.status == "open"

        subscription = Subscription.lock.find(invoice.subscription_id)
        invoice.update!(status: "paid", charge_status: "confirmed", paid_at: [@paid_at || Time.current, Time.current].min)
        settle_subscription(subscription, invoice)
        AuditEvent.record!(action: "subscription_invoice.paid", auditable: invoice,
          organization: Organization.find(@organization_id),
          changes: { amount: invoice.amount, period_start: invoice.period_start })
        invoice
      end
    end

    private

    def settle_subscription(subscription, invoice)
      changes = {}
      changes[:implementation_status] = "paid" if invoice.lines.any? { |line| line["implementation"] }
      delinquent = SubscriptionInvoice.open_invoices.where(subscription_id: subscription.id)
        .exists?(["due_on < ?", Time.zone.today - SubscriptionInvoice::GRACE_DAYS])
      changes[:status] = "active" if subscription.status == "past_due" && !delinquent
      subscription.update!(changes) if changes.any?
    end
  end
end
