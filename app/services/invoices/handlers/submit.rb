# frozen_string_literal: true

module Invoices
  module Handlers
    class Submit
      def call(event, context) = context.enqueue(Invoices::SubmitJob, event.organization_id, event.aggregate_id)
    end
  end
end
