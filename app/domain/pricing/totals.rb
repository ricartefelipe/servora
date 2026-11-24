# frozen_string_literal: true

module Pricing
  # Totals of a document made of lines plus a global discount.
  Totals = Data.define(:subtotal, :discount, :total, :estimated_cost) do
    def self.from(lines, discount: 0)
      subtotal = lines.sum(BigDecimal("0"), &:total)
      global_discount = Amount.money(discount)
      raise Amount::InvalidValue, "discount cannot be negative" if global_discount.negative?
      raise Amount::InvalidValue, "discount exceeds the subtotal" if global_discount > subtotal

      costs = lines.map(&:cost_total)
      estimated_cost = costs.any?(&:nil?) ? nil : costs.sum(BigDecimal("0"))
      new(subtotal:, discount: global_discount, total: subtotal - global_discount, estimated_cost:)
    end

    def margin
      return nil if estimated_cost.nil?

      total - estimated_cost
    end

    # Margin over revenue, in percent with one decimal; nil without revenue/cost.
    def margin_percent
      return nil if margin.nil? || total.zero?

      (margin / total * 100).round(1, BigDecimal::ROUND_HALF_UP)
    end
  end
end
