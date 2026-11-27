# frozen_string_literal: true

module Reports
  # Percentage in a report, kept as a number so the screen formats it for
  # pt-BR ("92,3%") while the CSV export stays machine-friendly ("92.3").
  Percent = Data.define(:value) do
    # Share of part over total with one decimal; nil without a total.
    def self.of(part, total)
      return nil if total.to_i.zero?

      new(value: (BigDecimal(part) * 100 / total).round(1, BigDecimal::ROUND_HALF_UP))
    end
  end
end
