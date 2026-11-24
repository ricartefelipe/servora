# frozen_string_literal: true

module Receivables
  # Records money given back to the customer. Never above what the payment (and
  # the receivable) still holds. Lock order: receivable → payment.
  #
  # Refunds of provider charges are then executed at the provider after commit
  # (payment_refund.requested); refunds of manual payments are flagged for the
  # finance team (PaymentRefund "manual").
  class RefundPayment
    def initialize(payment:, amount:, reason:, actor:)
      @payment = payment
      @amount = amount
      @reason = reason.to_s.strip
      @actor = actor
    end

    def call
      raise Errors::Invalid, "Informe o motivo do estorno." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        receivable = Receivable.lock("FOR NO KEY UPDATE").find(@payment.receivable_id)
        @payment.lock!
        refund(receivable)
      end
    rescue Receivables::Rejected => e
      raise Errors.translate(e)
    end

    private

    def refund(receivable)
      position = receivable.position.refund(@amount, refundable: @payment.refundable)
      refunded = position.refunded - receivable.refunded_amount
      @payment.update!(refunded_amount: @payment.refunded_amount + refunded)
      Errors.apply!(receivable, position)
      FinancialEvent.record!(receivable:, kind: "refund", amount: refunded, payment: @payment, actor: @actor,
        details: { reason: @reason })
      AuditEvent.record!(action: "receivable.refunded", auditable: receivable, changes: { amount: refunded, reason: @reason })
      schedule_execution(receivable, refunded)
      @payment
    end

    def schedule_execution(receivable, amount)
      via_provider = @payment.payment_charge_id.present?
      refund = PaymentRefund.create!(organization_id: receivable.organization_id, payment: @payment, receivable:, amount:,
        reason: @reason, status: via_provider ? "pending" : "manual", requested_by_membership_id: @actor&.id)
      return unless via_provider

      Outbox::Publisher.publish!(event_type: "payment_refund.requested", aggregate: refund,
        dedup_key: "payment_refund.requested:#{refund.id}")
    end
  end
end
