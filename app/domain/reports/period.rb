# frozen_string_literal: true

module Reports
  # Reporting period [from, to] (inclusive dates) in the organization's time
  # zone. Invalid or missing input falls back to the current month; ranges are
  # limited to MAX_DAYS so every report stays a bounded aggregate.
  Period = Data.define(:from, :to)

  class Period
    MAX_DAYS = 366

    def self.parse(from:, to:, today:)
      first = safe_date(from) || today.beginning_of_month
      last = safe_date(to) || today
      first, last = last, first if first > last
      first = last - (MAX_DAYS - 1) if (last - first).to_i >= MAX_DAYS
      new(from: first, to: last)
    end

    def self.safe_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    # Half-open time range covering the whole days in the zone.
    def range(zone) = from.in_time_zone(zone)...(to + 1).in_time_zone(zone)
    def days = (to - from).to_i + 1
    def label = "#{from.strftime("%d/%m/%Y")} a #{to.strftime("%d/%m/%Y")}"
    def to_param = { de: from.iso8601, ate: to.iso8601 }
  end
end
