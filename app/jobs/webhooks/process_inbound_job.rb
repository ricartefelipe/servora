# frozen_string_literal: true

module Webhooks
  class ProcessInboundJob < ApplicationJob
    queue_as :integrations

    def perform(organization_id, inbound_webhook_id)
      Webhooks::ProcessPaymentNotification.new(organization_id:, inbound_webhook_id:).call
    end
  end
end
