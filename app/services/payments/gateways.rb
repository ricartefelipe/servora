# frozen_string_literal: true

module Payments
  # Payment provider adapters. Every adapter implements:
  #
  #   create_charge(charge, customer) → RemoteCharge
  #   find_charge(charge)             → RemoteCharge or nil (lookup by our external_reference)
  #   cancel_charge(charge)           → nil
  #   refund_charge(charge, refund)   → RemoteRefund (not idempotent: never retried blindly)
  #
  # and raises Errors::Unavailable (request not delivered: safe to retry),
  # Errors::AmbiguousResponse (may have been processed: query before retrying)
  # or Errors::Rejected (definitive refusal).
  module Gateways
    RemoteCharge = Data.define(:external_id, :status, :payment_url, :paid_at, :amount)
    RemoteRefund = Data.define(:external_id, :status)

    module_function

    def for(integration)
      case integration.provider
      when "simulator" then Simulator.new
      when "asaas" then Asaas.new(api_key: integration.api_key)
      else raise ArgumentError, "unknown payment provider: #{integration.provider}"
      end
    end
  end
end
