# frozen_string_literal: true

module Pricing
  # One priced line: total = round(quantity × unit price, 2) − discount.
  Line = Data.define(:quantity, :unit_price, :discount, :unit_cost) do
    def self.build(quantity:, unit_price:, discount: 0, unit_cost: nil)
      new(
        quantity: Amount.quantity(quantity), unit_price: Amount.money(unit_price),
        discount: Amount.money(discount), unit_cost: unit_cost.nil? ? nil : Amount.cost(unit_cost)
      )
    end

    def initialize(quantity:, unit_price:, discount:, unit_cost:)
      raise Amount::InvalidValue, "quantity must be positive" unless quantity.positive?
      raise Amount::InvalidValue, "unit price cannot be negative" if unit_price.negative?
      raise Amount::InvalidValue, "discount cannot be negative" if discount.negative?

      super
      raise Amount::InvalidValue, "discount exceeds the line value" if discount > gross
    end

    def gross = Amount.money(quantity * unit_price)
    def total = gross - discount

    # Estimated internal cost of the line (nil when the cost is unknown).
    def cost_total = unit_cost && Amount.money(quantity * unit_cost)
  end
end
