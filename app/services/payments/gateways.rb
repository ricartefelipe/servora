# frozen_string_literal: true

module Payments
  # Payment provider adapters. Every adapter implements:
  #
  #   create_charge(charge, customer) → RemoteCharge
  #   find_charge(charge)             → RemoteCharge or nil (lookup by our external_reference)
  #   cancel_charge(charge)           → nil
  #
  # and raises Errors::Unavailable (request not delivered: safe to retry),
  # Errors::AmbiguousResponse (may have been processed: query before retrying)
  # or Errors::Rejected (definitive refusal).
  module Gateways
    RemoteCharge = Data.define(:external_id, :status, :payment_url, :paid_at, :amount)
    # Charge data of a platform subscription invoice (same interface as PaymentCharge).
    PlatformCharge = Data.define(:external_reference, :external_id, :amount, :due_on, :billing_type, :attempts, :status)
    # The organization as a customer of the platform.
    PlatformCustomer = Data.define(:id, :name, :document, :email)

    module_function

    # Gateway of the platform's own payment account (subscription invoices).
    # Credentials come from the environment, never from tenant data.
    def for_platform
      case ENV.fetch("PLATFORM_PAYMENT_PROVIDER", "simulator")
      when "asaas" then Asaas.new(api_key: ENV.fetch("PLATFORM_ASAAS_API_KEY"))
      else Simulator.new
      end
    end

    def platform_provider = ENV.fetch("PLATFORM_PAYMENT_PROVIDER", "simulator")

    def for(integration)
      case integration.provider
      when "simulator" then Simulator.new
      when "asaas" then Asaas.new(api_key: integration.api_key)
      else raise ArgumentError, "unknown payment provider: #{integration.provider}"
      end
    end
  end
end
