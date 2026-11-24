# frozen_string_literal: true

module Payments
  class SyncChargeJob < ApplicationJob
    queue_as :integrations

    retry_on Payments::Gateways::Errors::Unavailable, Payments::Gateways::Errors::AmbiguousResponse,
      wait: :polynomially_longer, attempts: 3
    discard_on Payments::Gateways::Errors::Rejected

    def perform(organization_id, charge_id)
      Payments::SyncCharge.new(organization_id:, charge_id:).call
    end
  end
end
