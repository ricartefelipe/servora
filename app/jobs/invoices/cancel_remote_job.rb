# frozen_string_literal: true

module Invoices
  class CancelRemoteJob < ApplicationJob
    queue_as :integrations

    retry_on Payments::Gateways::Errors::Unavailable, Payments::Gateways::Errors::AmbiguousResponse,
      wait: :polynomially_longer, attempts: 8

    def perform(organization_id, invoice_id)
      Invoices::CancelRemote.new(organization_id:, invoice_id:).call
    end
  end
end
