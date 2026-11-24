# frozen_string_literal: true

module Payments
  module Handlers
    # payment_charge.canceled → cancellation at the provider (after commit).
    class CancelRemoteCharge
      def call(event, context)
        context.enqueue(Payments::CancelRemoteChargeJob, event.organization_id, event.aggregate_id)
      end
    end
  end
end
