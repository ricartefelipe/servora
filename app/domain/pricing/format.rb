# frozen_string_literal: true

module Pricing
  # Text formatting of money for messages, without Float conversion.
  module Format
    module_function

    # 1500.5 → "R$ 1.500,50"
    def brl(value)
      amount = Amount.money(value)
      whole, cents = amount.abs.to_s("F").split(".")
      grouped = whole.reverse.scan(/\d{1,3}/).join(".").reverse
      "#{"-" if amount.negative?}R$ #{grouped},#{cents.ljust(2, "0")}"
    end
  end
end
