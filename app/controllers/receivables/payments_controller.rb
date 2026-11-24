# frozen_string_literal: true

module Receivables
  class PaymentsController < BaseController
    def new
      authorize @receivable, :register_payment?
      @form = PaymentForm.new(amount: @receivable.balance.to_s("F"))
    end

    def create
      authorize @receivable, :register_payment?
      @form = PaymentForm.new(params.expect(payment: PaymentForm.fields))
      return invalid unless @form.valid? && @form.paid_at

      Receivables::RegisterPayment.new(receivable: @receivable, amount: @form.amount, payment_method: @form.payment_method,
        paid_at: @form.paid_at, notes: @form.notes, idempotency_key: @form.operation_key, actor: current_membership).call
      back("Pagamento registrado.")
    rescue Servora::RuleViolation, Pricing::Amount::InvalidValue => e
      @form.errors.add(:base, e.is_a?(Servora::RuleViolation) ? e.message : "Informe um valor válido.")
      invalid
    end

    def refund
      authorize @receivable, :refund?
      payment = tenant_relation(Payment).where(receivable_id: @receivable.id).find(params.expect(:id))
      attributes = params.expect(refund: %i[amount reason])
      Receivables::RefundPayment.new(payment:, amount: attributes[:amount], reason: attributes[:reason],
        actor: current_membership).call
      back("Estorno registrado.")
    rescue Pricing::Amount::InvalidValue
      redirect_to receivable_path(@receivable), alert: "Informe um valor válido.", status: :see_other
    end

    private

    def invalid
      @form.errors.add(:paid_on, "é inválida") if @form.paid_at.nil? && @form.errors.empty?
      render_invalid_form(partial: "receivables/payments/form", template: :new, form: @form, receivable: @receivable)
    end
  end
end
