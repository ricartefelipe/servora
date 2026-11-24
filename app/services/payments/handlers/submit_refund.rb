# frozen_string_literal: true

module Payments
  module Handlers
    # payment_refund.requested → provider refund job (after commit).
    class SubmitRefund
      def call(event, context)
        context.enqueue(Payments::SubmitRefundJob, event.organization_id, event.aggregate_id)
      end
    end
  end
end
