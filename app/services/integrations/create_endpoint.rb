# frozen_string_literal: true

module Integrations
  # Registers an outbound webhook endpoint. Returns [endpoint, secret]; the
  # signing secret is stored encrypted and shown once.
  class CreateEndpoint
    def initialize(organization:, url:, events:, description: nil)
      @organization = organization
      @url = url.to_s.strip
      @events = Array(events).compact_blank
      @description = description
    end

    def call
      secret = WebhookEndpoint.generate_secret
      endpoint = WebhookEndpoint.create!(organization_id: @organization.id, url: @url, description: @description,
        events: @events, secret:)
      AuditEvent.record!(action: "webhook_endpoint.created", auditable: endpoint, changes: { url: @url, events: @events })
      [endpoint, secret]
    end
  end
end
