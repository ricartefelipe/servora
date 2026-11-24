# frozen_string_literal: true

module Webhooks
  class DeliverJob < ApplicationJob
    queue_as :integrations

    retry_on Webhooks::Deliver::Retry, wait: :polynomially_longer, attempts: Webhooks::Deliver::MAX_ATTEMPTS

    def perform(organization_id, delivery_id)
      Webhooks::Deliver.new(organization_id:, delivery_id:).call
    end
  end
end
