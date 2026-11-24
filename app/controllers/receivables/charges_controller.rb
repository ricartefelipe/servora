# frozen_string_literal: true

module Receivables
  # Provider charges. Submission and reconciliation run in background jobs;
  # these actions only request them (never block on the provider).
  class ChargesController < BaseController
    def create
      authorize @receivable, :charge?
      Payments::RequestCharge.new(receivable: @receivable, actor: current_membership,
        billing_type: params.dig(:charge, :billing_type)).call
      back("Cobrança solicitada. O envio ao provedor ocorre em segundo plano.")
    end

    def simulate
      authorize @receivable, :charge?
      Payments::SimulatePayment.new(charge: load_charge, actor: current_membership).call
      back("Pagamento simulado confirmado.")
    end

    def sync
      authorize @receivable, :charge?
      Payments::SyncChargeJob.perform_later(@receivable.organization_id, load_charge.id)
      back("Consulta ao provedor solicitada.")
    end

    private

    def load_charge = tenant_relation(PaymentCharge).where(receivable_id: @receivable.id).find(params.expect(:id))
  end
end
