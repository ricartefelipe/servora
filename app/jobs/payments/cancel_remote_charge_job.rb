# frozen_string_literal: true

module Payments
  class CancelRemoteChargeJob < ApplicationJob
    queue_as :integrations

    retry_on Payments::Gateways::Errors::Unavailable, Payments::Gateways::Errors::AmbiguousResponse,
      wait: :polynomially_longer, attempts: 8

    def perform(organization_id, charge_id)
      Payments::CancelRemoteCharge.new(organization_id:, charge_id:).call
    end
  end
end
