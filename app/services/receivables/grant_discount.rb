# frozen_string_literal: true

module Receivables
  # Discount on the open balance. Requires its own permission (checked by the
  # policy) and a reason kept in the history and the audit trail.
  class GrantDiscount
    def initialize(receivable:, amount:, reason:, actor:)
      @receivable = receivable
      @amount = amount
      @reason = reason.to_s.strip
      @actor = actor
    end

    def call
      raise Errors::Invalid, "Informe o motivo do desconto." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        Errors.lock_outstanding!(@receivable)
        position = @receivable.position.grant_discount(@amount)
        granted = position.discount - @receivable.discount_amount
        Errors.apply!(@receivable, position)
        FinancialEvent.record!(receivable: @receivable, kind: "discount", amount: granted, actor: @actor,
          details: { reason: @reason })
        AuditEvent.record!(action: "receivable.discount_granted", auditable: @receivable,
          changes: { amount: granted, reason: @reason })
        @receivable
      end
    rescue Receivables::Rejected => e
      raise Errors.translate(e)
    end
  end
end
