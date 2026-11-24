# frozen_string_literal: true

module Receivables
  class DiscountsController < BaseController
    def new
      authorize @receivable, :discount?
      @form = DiscountForm.new
    end

    def create
      authorize @receivable, :discount?
      @form = DiscountForm.new(params.expect(discount: DiscountForm.fields))
      return invalid unless @form.valid?

      Receivables::GrantDiscount.new(receivable: @receivable, amount: @form.amount, reason: @form.reason,
        actor: current_membership).call
      back("Desconto concedido.")
    rescue Servora::RuleViolation, Pricing::Amount::InvalidValue => e
      @form.errors.add(:base, e.is_a?(Servora::RuleViolation) ? e.message : "Informe um valor válido.")
      invalid
    end

    private

    def invalid
      render_invalid_form(partial: "receivables/discounts/form", template: :new, form: @form, receivable: @receivable)
    end
  end
end
