# frozen_string_literal: true

module Subscriptions
  # Daily billing of one subscription (prepaid monthly periods anchored on the
  # activation date, month ends preserved like the preventive schedules):
  #
  # * creates the invoice of the current period if missing — (subscription,
  #   period_start) is unique, so repeated runs never duplicate it; the amount
  #   is frozen from the subscription, plus the implementation fee on the
  #   first invoice while it is pending;
  # * publishes the charge request to the outbox (provider call after commit);
  # * applies delinquency: an invoice overdue for more than GRACE_DAYS turns an
  #   active subscription into past_due (read-only); paying reactivates it.
  class Bill
    DUE_AFTER_DAYS = 5

    def initialize(subscription:, today: Time.zone.today)
      @subscription = subscription
      @today = today
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @subscription.lock!
        next unless billable?

        invoice = current_invoice || create_invoice
        apply_delinquency
        invoice
      end
    end

    private

    def billable? = %w[active past_due].include?(@subscription.status) && @subscription.activated_at.present?

    def period
      anchor = @subscription.activated_at.in_time_zone.to_date
      frequency = Preventive::Frequency.new(unit: "month", interval: 1)
      months = ((@today.year * 12) + @today.month) - ((anchor.year * 12) + anchor.month)
      months -= 1 while months.positive? && frequency.advance(anchor, months) > @today
      [frequency.advance(anchor, months), frequency.advance(anchor, months + 1)]
    end

    def current_invoice = SubscriptionInvoice.find_by(subscription_id: @subscription.id, period_start: period.first)

    def create_invoice
      start, finish = period
      lines = billing_lines
      invoice = SubscriptionInvoice.create!(
        organization_id: @subscription.organization_id, subscription: @subscription, period_start: start, period_end: finish,
        due_on: start + DUE_AFTER_DAYS, amount: lines.sum { |line| BigDecimal(line["amount"]) }, lines:,
        provider: Payments::Gateways.platform_provider,
        external_reference: "plat-#{@subscription.organization_id}-#{SecureRandom.uuid_v7}"
      )
      @subscription.update!(current_period_end: finish)
      Outbox::Publisher.publish!(event_type: "subscription_invoice.created", aggregate: invoice,
        dedup_key: "subscription_invoice.created:#{invoice.id}")
      invoice
    end

    def billing_lines
      plan = @subscription.plan
      lines = [{ "description" => "Plano #{plan.name}", "amount" => @subscription.monthly_amount.to_s("F") }]
      return lines unless @subscription.implementation_status == "pending" && @subscription.implementation_fee.positive?
      return lines if SubscriptionInvoice.exists?(subscription_id: @subscription.id)

      lines << { "description" => "Implantação e treinamento", "amount" => @subscription.implementation_fee.to_s("F"),
                 "implementation" => true }
    end

    def apply_delinquency
      return unless @subscription.status == "active"
      return unless SubscriptionInvoice.open_invoices.where(subscription_id: @subscription.id)
        .exists?(["due_on < ?", @today - SubscriptionInvoice::GRACE_DAYS])

      @subscription.update!(status: "past_due")
      AuditEvent.record!(action: "subscription.past_due", auditable: @subscription,
        organization: Organization.find(@subscription.organization_id))
    end
  end
end
