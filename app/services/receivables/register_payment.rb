# frozen_string_literal: true

module Receivables
  # Registers money received. Partial payments are allowed; overpayment is not.
  # With an idempotency key (form resubmission, provider confirmation retried)
  # the payment is recorded once.
  class RegisterPayment
    def initialize(receivable:, amount:, payment_method:, actor:, paid_at: nil, idempotency_key: nil, charge: nil, notes: nil)
      @receivable = receivable
      @amount = Pricing::Amount.money(amount)
      @payment_method = payment_method.to_s
      @actor = actor
      @paid_at = paid_at || Time.current
      @idempotency_key = idempotency_key.presence
      @charge = charge
      @notes = notes.to_s.strip.presence
    end

    def call
      validate!
      IdempotentOperation.perform(@idempotency_key, find: -> { Payment.find_by(idempotency_key: @idempotency_key) },
        same: ->(payment) { payment.receivable_id == @receivable.id && payment.amount == @amount }) do
        ActiveRecord::Base.transaction(requires_new: true) { register }
      end
    rescue Receivables::Rejected => e
      raise Errors.translate(e)
    end

    private

    def validate!
      raise Errors::Invalid, "Forma de pagamento inválida." unless Payment::METHODS.key?(@payment_method)
      raise Errors::Invalid, "A data do pagamento não pode estar no futuro." if @paid_at > 5.minutes.from_now
    end

    def register
      Errors.lock_outstanding!(@receivable)
      position = @receivable.position.pay(@amount)
      payment = Payment.create!(organization_id: @receivable.organization_id, receivable: @receivable, amount: @amount,
        payment_method: @payment_method, paid_at: @paid_at, idempotency_key: @idempotency_key, notes: @notes,
        payment_charge_id: @charge&.id, recorded_by_membership_id: @actor&.id)
      Errors.apply!(@receivable, position)
      FinancialEvent.record!(receivable: @receivable, kind: "payment", amount: @amount, payment:, actor: @actor,
        details: { method: @payment_method, balance: position.balance })
      AuditEvent.record!(action: "receivable.payment_registered", auditable: @receivable,
        changes: { amount: @amount, method: @payment_method, status: position.status })
      if position.settled?
        Outbox::Publisher.publish!(event_type: "receivable.settled", aggregate: @receivable,
          dedup_key: "receivable.settled:#{@receivable.id}:#{@receivable.paid_amount}")
      end
      payment
    end
  end
end
