# frozen_string_literal: true

module Webhooks
  module Handlers
    # Creates one delivery per subscribed endpoint (unique per endpoint and
    # event, so reprocessing the outbox event does not duplicate deliveries)
    # and schedules the HTTP calls after commit.
    class Fanout
      def call(event, context)
        endpoints = WebhookEndpoint.subscribed_to(event.event_type).pluck(:id)
        return if endpoints.empty?

        payload = Webhooks::Payload.for(event)
        rows = endpoints.map do |endpoint_id|
          { organization_id: event.organization_id, webhook_endpoint_id: endpoint_id, event_id: event.id,
            event_type: event.event_type, payload: }
        end
        WebhookDelivery.insert_all(rows, unique_by: %i[webhook_endpoint_id event_id]) # rubocop:disable Rails/SkipsModelValidations -- conflict-tolerant fan-out
        # Reprocessing the event re-schedules deliveries still pending (the
        # delivery claims its row, so a duplicate job is harmless).
        WebhookDelivery.where(event_id: event.id, status: "pending").pluck(:id).each do |delivery_id|
          context.enqueue(Webhooks::DeliverJob, event.organization_id, delivery_id)
        end
      end
    end
  end
end
