# frozen_string_literal: true

module Receivables
  # Resolution of refunds that need attention (unknown outcome, refused,
  # manual execution).
  class RefundsController < BaseController
    def resolve
      authorize @receivable, :refund?
      refund = tenant_relation(PaymentRefund).where(receivable_id: @receivable.id).find(params.expect(:id))
      Payments::ResolveRefund.new(refund:, action: params.expect(resolution: [:action])[:action], actor: current_membership).call
      back(refund.reload.status == "pending" ? "Estorno reenviado ao provedor." : "Estorno marcado como executado.")
    end
  end
end
