# frozen_string_literal: true

module Webhooks
  module Handlers
    # inbound_webhook.received → processing job (after commit).
    class ProcessInbound
      def call(event, context)
        context.enqueue(Webhooks::ProcessInboundJob, event.organization_id, event.aggregate_id)
      end
    end
  end
end
