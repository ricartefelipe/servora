# frozen_string_literal: true

module Payments
  # Confirms a charge of the simulated provider, as the provider would after the
  # customer pays. Not available for real providers.
  class SimulatePayment
    def initialize(charge:, actor:)
      @charge = charge
      @actor = actor
    end

    def call
      unless @charge.simulated?
        raise Receivables::Errors::Invalid,
          "Somente cobranças do simulador podem ser confirmadas manualmente."
      end
      raise Receivables::Errors::Invalid, "A cobrança ainda não foi registrada no provedor." unless @charge.status == "submitted"

      ConfirmCharge.new(organization_id: @charge.organization_id, charge_id: @charge.id, actor: @actor).call
    end
  end
end
