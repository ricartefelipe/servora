# frozen_string_literal: true

module Pricing
  # Monetary and quantity arithmetic rules (BRL).
  #
  # * money: BigDecimal, 2 decimals, commercial rounding (half up), matching
  #   PostgreSQL round(numeric, 2) used by database constraints;
  # * quantities: up to 3 decimals; unit costs: up to 4 decimals;
  # * Float is never accepted: values arrive as String, Integer or BigDecimal.
  module Amount
    MONEY_SCALE = 2
    QUANTITY_SCALE = 3
    COST_SCALE = 4

    class InvalidValue < ArgumentError; end

    module_function

    def decimal(value)
      case value
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when String then parse(value)
      when nil then BigDecimal("0")
      else raise InvalidValue, "unsupported numeric type: #{value.class}"
      end
    end

    def money(value) = decimal(value).round(MONEY_SCALE, BigDecimal::ROUND_HALF_UP)
    def quantity(value) = decimal(value).round(QUANTITY_SCALE, BigDecimal::ROUND_HALF_UP)
    def cost(value) = decimal(value).round(COST_SCALE, BigDecimal::ROUND_HALF_UP)

    # Accepts "1234.56", "1234,56" and "1.234,56".
    def parse(text)
      cleaned = text.to_s.strip.delete(" ")
      raise InvalidValue, "empty value" if cleaned.empty?

      cleaned = cleaned.delete(".").tr(",", ".") if cleaned.include?(",")
      raise InvalidValue, "invalid number: #{text}" unless cleaned.match?(/\A-?\d+(\.\d+)?\z/)

      BigDecimal(cleaned)
    end
  end
end
