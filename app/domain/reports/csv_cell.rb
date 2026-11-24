# frozen_string_literal: true

module Reports
  # Values written to CSV exports. Text starting with a formula trigger
  # (=, +, -, @, tab, carriage return) is prefixed with an apostrophe so
  # spreadsheet applications treat it as text (CSV/formula injection).
  module CsvCell
    TRIGGERS = ["=", "+", "-", "@", "\t", "\r"].freeze

    module_function

    def safe(value)
      case value
      when nil then ""
      when Money then value.value.to_s("F")
      when BigDecimal then value.to_s("F")
      when Numeric then value.to_s
      when Date, Time then value.iso8601
      else text(value.to_s)
      end
    end

    def text(value) = TRIGGERS.any? { |trigger| value.start_with?(trigger) } ? "'#{value}" : value
  end
end
