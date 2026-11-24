# frozen_string_literal: true

module Quotes
  class UpdateTerms
    include DraftEditing

    class InvalidTerms < Servora::RuleViolation; end

    def initialize(version:, valid_until:, discount:, payment_terms:, notes:)
      @version = version
      @valid_until = valid_until
      @discount = discount
      @payment_terms = payment_terms
      @notes = notes
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @version.lock!
        ensure_draft!(@version)
        totals = Pricing::Totals.from(@version.items.map(&:pricing_line), discount: @discount.presence || 0)
        @version.update!(valid_until: @valid_until, payment_terms: @payment_terms, notes: @notes,
          discount_amount: totals.discount, subtotal: totals.subtotal, total: totals.total)
      end
      @version
    rescue Pricing::Amount::InvalidValue
      raise InvalidTerms, "O desconto deve ser positivo e não pode superar o subtotal."
    end
  end
end
