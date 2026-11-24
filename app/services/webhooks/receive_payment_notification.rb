# frozen_string_literal: true

module Webhooks
  # Persists a provider notification before acknowledging it. Duplicates
  # (same provider event id) are accepted and ignored; processing happens
  # after commit through the outbox.
  class ReceivePaymentNotification
    def initialize(organization_id:, payload:)
      @organization_id = organization_id
      @payload = payload
    end

    def call
      event_id = @payload["id"].to_s.presence || raise(ArgumentError, "missing event id")
      Servora::Tenancy.with_organization(@organization_id) do
        id = InboundWebhook.insert({ organization_id: @organization_id, provider: "asaas", external_event_id: event_id.first(120), # rubocop:disable Rails/SkipsModelValidations -- conflict-tolerant insert is the deduplication
                                     event_type: @payload["event"].to_s.first(80), payload: @payload },
          unique_by: :index_inbound_webhooks_dedup, returning: :id).rows.first&.first
        next :duplicate unless id

        Outbox::Publisher.publish!(event_type: "inbound_webhook.received", aggregate: InboundWebhook.find(id),
          dedup_key: "inbound_webhook.received:#{id}")
        :accepted
      end
    end
  end
end
