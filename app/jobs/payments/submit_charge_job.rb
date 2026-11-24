# frozen_string_literal: true

module Payments
  # Submission retries query the provider by reference before creating again.
  class SubmitChargeJob < ApplicationJob
    queue_as :integrations

    retry_on Payments::Gateways::Errors::Unavailable, Payments::Gateways::Errors::AmbiguousResponse,
      wait: :polynomially_longer, attempts: 8

    def perform(organization_id, charge_id)
      Payments::SubmitCharge.new(organization_id:, charge_id:).call
    end
  end
end
