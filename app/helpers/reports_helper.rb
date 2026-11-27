# frozen_string_literal: true

module ReportsHelper
  def report_value(value)
    case value
    when Reports::Money then money(value.value)
    when Reports::Percent then percentage(value.value)
    when BigDecimal then number_with_precision(value, precision: 1, strip_insignificant_zeros: true, separator: ",",
      delimiter: ".")
    when nil then "—"
    else value
    end
  end
end
