# frozen_string_literal: true

module Subscriptions
  # Monthly amount of a platform subscription:
  #   plan price + extra technician seats × seat price + add-on modules not
  #   already included in the plan. Money in BRL with 2 decimals.
  Pricing = Data.define(:plan_price, :included_technicians, :extra_technician_price, :plan_modules, :module_prices) do
    def monthly_amount(seats:, addons:)
      raise ArgumentError, "seats must be positive" unless seats.to_i.positive?

      extra_seats = [seats.to_i - included_technicians, 0].max
      addon_total = billable_addons(addons).sum(BigDecimal("0")) { |code| module_prices.fetch(code) }
      ::Pricing::Amount.money(plan_price + (extra_seats * extra_technician_price) + addon_total)
    end

    # Add-ons that are known and not already part of the plan.
    def billable_addons(addons) = (Array(addons) & module_prices.keys) - plan_modules

    def modules(addons) = (plan_modules + billable_addons(addons)).uniq.sort
  end
end
