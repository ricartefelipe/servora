# frozen_string_literal: true

module Subscriptions
  module Handlers
    # subscription_invoice.created → platform charge (after commit).
    class SubmitInvoiceCharge
      def call(event, context) = context.enqueue(Subscriptions::SubmitInvoiceChargeJob, event.organization_id, event.aggregate_id)
    end
  end
end
