# frozen_string_literal: true

module Reports
  # Monetary value in a report (BRL), so screens and exports format it
  # explicitly instead of guessing from column names.
  Money = Data.define(:value) do
    def self.of(value) = new(value: Pricing::Amount.money(value || 0))

    def +(other) = self.class.new(value: value + other.value)
  end
end
