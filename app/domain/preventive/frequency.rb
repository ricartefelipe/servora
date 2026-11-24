# frozen_string_literal: true

module Preventive
  # Calendar periodicity ("every N weeks/months/years").
  #
  # Dates are always computed from the anchor, never from the previous
  # occurrence, so month-end anchors are preserved: an anchor on Jan 31 gives
  # Feb 28 (or 29), Mar 31, Apr 30…; Feb 29 gives Feb 28 in common years and
  # Feb 29 again in leap years (Date#>> clamps to the last day of the month).
  Frequency = Data.define(:unit, :interval)

  class Frequency
    UNITS = { "week" => %w[semana semanas], "month" => %w[mês meses], "year" => %w[ano anos] }.freeze

    def initialize(unit:, interval:)
      raise ArgumentError, "unknown frequency unit: #{unit}" unless UNITS.key?(unit.to_s)
      raise ArgumentError, "interval must be between 1 and 104" unless interval.to_i.between?(1, 104)

      super(unit: unit.to_s, interval: interval.to_i)
    end

    def advance(date, steps)
      raise ArgumentError, "steps cannot be negative" if steps.negative?

      case unit
      when "week" then date + (7 * interval * steps)
      when "month" then date >> (interval * steps)
      else date >> (12 * interval * steps)
      end
    end

    def label
      singular, plural = UNITS.fetch(unit)
      interval == 1 ? "A cada #{singular}" : "A cada #{interval} #{plural}"
    end
  end
end
