# frozen_string_literal: true

module Receivables
  # Cancels a receivable without money kept (refund first). An in-flight
  # provider charge is canceled locally and remotely (after commit, through
  # the outbox), so the customer cannot pay a canceled debt.
  class Cancel
    def initialize(receivable:, reason:, actor:)
      @receivable = receivable
      @reason = reason.to_s.strip
      @actor = actor
    end

    def call
      raise Errors::Invalid, "Informe o motivo do cancelamento." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        Errors.lock_outstanding!(@receivable)
        @receivable.position.ensure_cancelable!
        @receivable.update!(status: "canceled", canceled_at: Time.current, cancel_reason: @reason, settled_at: nil)
        cancel_active_charge
        FinancialEvent.record!(receivable: @receivable, kind: "canceled", actor: @actor, details: { reason: @reason })
        AuditEvent.record!(action: "receivable.canceled", auditable: @receivable, changes: { reason: @reason })
        @receivable
      end
    rescue Receivables::Rejected => e
      raise Errors.translate(e)
    end

    private

    def cancel_active_charge
      charge = PaymentCharge.active.lock.find_by(receivable_id: @receivable.id)
      return unless charge

      charge.update!(status: "canceled")
      FinancialEvent.record!(receivable: @receivable, kind: "charge_canceled", amount: charge.amount, actor: @actor)
      return if charge.external_id.blank?

      Outbox::Publisher.publish!(event_type: "payment_charge.canceled", aggregate: charge,
        dedup_key: "payment_charge.canceled:#{charge.id}")
    end
  end
end
