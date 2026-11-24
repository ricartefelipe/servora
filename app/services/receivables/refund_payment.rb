# frozen_string_literal: true

module Receivables
  # Records money given back to the customer. Never above what the payment (and
  # the receivable) still holds. Lock order: receivable → payment.
  #
  # The refund is registered in Servora; executing it at the payment provider
  # is an operational step outside this use case.
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
      @payment
    end
  end
end
