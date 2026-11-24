# frozen_string_literal: true

module Payments
  # Only undelivered requests are retried; ambiguous outcomes wait for a person.
  class SubmitRefundJob < ApplicationJob
    queue_as :integrations

    retry_on Payments::Gateways::Errors::Unavailable, wait: :polynomially_longer, attempts: 8

    def perform(organization_id, refund_id)
      Payments::SubmitRefund.new(organization_id:, refund_id:).call
    end
  end
end
