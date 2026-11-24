# frozen_string_literal: true

# Platform plan (reference data, read-only for the application).
class Plan < ApplicationRecord
  scope :ordered, -> { order(:position) }

  def readonly? = true

  def pricing
    Subscriptions::Pricing.new(plan_price: monthly_price, included_technicians:, extra_technician_price:,
      plan_modules: modules, module_prices: PlanModule.price_table)
  end
end
