# frozen_string_literal: true

module Sla
  # Business time arithmetic in the organization's time zone.
  #
  # intervals: weekday (Date#wday, 0 = Sunday) → [[start_minute, end_minute)…]
  # holidays:  dates without business hours
  #
  # Interval boundaries are built with the zone's local clock (not by adding
  # seconds to midnight), so a day with a time zone offset change keeps its
  # local opening hours. Work is measured in seconds to avoid rounding drift.
  class BusinessCalendar
    MAX_DAYS = 3660
    FULL_DAY = [[0, 1440]].freeze

    def self.continuous(zone) = new(intervals: (0..6).index_with { FULL_DAY }, holidays: [], zone:)

    def initialize(intervals:, holidays:, zone:)
      @intervals = intervals.transform_values { |list| list.sort.freeze }.freeze
      @holidays = holidays.to_set.freeze
      @zone = zone.is_a?(ActiveSupport::TimeZone) ? zone : ActiveSupport::TimeZone[zone]
      raise ArgumentError, "unknown time zone: #{zone}" unless @zone
    end

    def business_hours? = @intervals.values.any?(&:any?)

    # Instant at which `seconds` of business time have elapsed after `from`.
    def add(from, seconds)
      remaining = seconds.to_i
      cursor = from.in_time_zone(@zone)
      return cursor if remaining <= 0

      each_window_from(cursor) do |window_start, window_end|
        start = [window_start, cursor].max
        available = window_end - start
        return start + remaining if remaining <= available

        remaining -= available
      end
    end

    # Business seconds between two instants (zero when `to` precedes `from`).
    def elapsed(from, to)
      from = from.in_time_zone(@zone)
      to = to.in_time_zone(@zone)
      return 0 if to <= from

      total = 0
      each_window_from(from) do |window_start, window_end|
        break if window_start >= to

        total += ([window_end, to].min - [window_start, from].max).to_i
      end
      total
    end

    private

    def each_window_from(cursor)
      raise ArgumentError, "calendar has no business hours" unless business_hours?

      day = cursor.to_date
      MAX_DAYS.times do
        windows(day).each do |window_start, window_end|
          yield window_start, window_end if window_end > cursor
        end
        day += 1
      end
      raise ArgumentError, "no business time within #{MAX_DAYS} days"
    end

    def windows(day)
      return [] if @holidays.include?(day)

      @intervals.fetch(day.wday, []).map { |start_minute, end_minute| [local(day, start_minute), local(day, end_minute)] }
    end

    def local(day, minute)
      return local(day + 1, 0) if minute >= 1440

      @zone.local(day.year, day.month, day.day, minute / 60, minute % 60)
    end
  end
end
