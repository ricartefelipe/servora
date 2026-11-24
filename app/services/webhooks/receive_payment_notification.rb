# frozen_string_literal: true

module Webhooks
  # Persists a provider notification before acknowledging it. Duplicates
  # (same provider event id) are accepted and ignored; processing happens
  # after commit through the outbox.
  class ReceivePaymentNotification
    def initialize(organization_id:, payload:, provider: "asaas")
      @organization_id = organization_id
      @payload = payload
      @provider = provider
    end

    def call
      event_id = @payload["id"].to_s.presence || raise(ArgumentError, "missing event id")
      Servora::Tenancy.with_organization(@organization_id) do
        row = { organization_id: @organization_id, provider: @provider, external_event_id: event_id.first(120),
                event_type: @payload["event"].to_s.first(80), payload: @payload }
        # Conflict-tolerant insert: the unique index is the deduplication.
        id = InboundWebhook.insert(row, unique_by: :index_inbound_webhooks_dedup, returning: :id).rows.first&.first # rubocop:disable Rails/SkipsModelValidations
        next :duplicate unless id

        Outbox::Publisher.publish!(event_type: "inbound_webhook.received", aggregate: InboundWebhook.find(id),
          dedup_key: "inbound_webhook.received:#{id}")
        :accepted
      end
    end
  end
end
