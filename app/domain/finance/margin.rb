# frozen_string_literal: true

module Finance
  # Margin of a work order. Predicted comes from the authorized items (price
  # and estimated unit cost); realized uses what was billed (net of discounts
  # and cancellations) against the costs actually recorded: material at the
  # cost of the moment of consumption, labor at the hourly cost in force when
  # time was logged, and expenses.
  Margin = Data.define(:revenue, :material_cost, :labor_cost, :expenses) do
    def self.build(revenue:, material_cost: 0, labor_cost: 0, expenses: 0)
      money = ->(value) { Pricing::Amount.money(value) }
      new(revenue: money.call(revenue), material_cost: money.call(material_cost), labor_cost: money.call(labor_cost),
        expenses: money.call(expenses))
    end

    def total_cost = material_cost + labor_cost + expenses
    def margin = revenue - total_cost

    # Percentage over revenue with one decimal; nil without revenue.
    def margin_percent
      return nil if revenue.zero?

      (margin / revenue * 100).round(1, BigDecimal::ROUND_HALF_UP)
    end
  end
end
