# frozen_string_literal: true

module Invoices
  module Handlers
    class CancelRemote
      def call(event, context) = context.enqueue(Invoices::CancelRemoteJob, event.organization_id, event.aggregate_id)
    end
  end
end
