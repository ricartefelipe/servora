# frozen_string_literal: true

module Payments
  # Payment provider adapters. Every adapter implements:
  #
  #   create_charge(charge, customer) → RemoteCharge
  #   find_charge(charge)             → RemoteCharge or nil (lookup by our external_reference)
  #   cancel_charge(charge)           → nil
  #   issue_invoice(invoice, customer, settings, charge) → RemoteInvoice
  #   find_invoice(invoice)           → RemoteInvoice or nil (by external reference)
  #   cancel_invoice(invoice)         → RemoteInvoice
  #
  # and raises Errors::Unavailable (request not delivered: safe to retry),
  # Errors::AmbiguousResponse (may have been processed: query before retrying)
  # or Errors::Rejected (definitive refusal).
  module Gateways
    RemoteCharge = Data.define(:external_id, :status, :payment_url, :paid_at, :amount)
    RemoteInvoice = Data.define(:external_id, :status, :number, :verification_code, :pdf_url, :xml_url, :message)

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
