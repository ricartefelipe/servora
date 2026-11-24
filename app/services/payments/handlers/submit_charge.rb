# frozen_string_literal: true

module Payments
  module Handlers
    # payment_charge.requested → provider submission job (after commit).
    class SubmitCharge
      def call(event, context)
        context.enqueue(Payments::SubmitChargeJob, event.organization_id, event.aggregate_id)
      end
    end
  end
end
