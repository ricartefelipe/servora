# frozen_string_literal: true

module Scheduling
  # Start proposed by the "schedule a visit" form: 09:00 on the next business
  # day after today. Business days follow the organization's opening hours and
  # holidays when they are configured (Monday to Friday otherwise); when the
  # office opens after 09:00, or closes before it, the proposal moves to the
  # day's first opening.
  #
  # opening_hours: weekday (Date#wday, 0 = Sunday) → [[start_minute, end_minute)…]
  # holidays:      dates without business hours
  class DefaultStart
    PREFERRED_MINUTE = 9 * 60
    FALLBACK_WEEKDAYS = (1..5)
    HORIZON_DAYS = 31

    def initialize(now:, opening_hours: {}, holidays: [])
      @now = now
      @opening_hours = opening_hours.transform_values(&:sort)
      @holidays = holidays.to_set
    end

    def call
      first_day = @now.to_date + 1
      (first_day...(first_day + HORIZON_DAYS)).each do |day|
        minute = start_minute(day)
        return at(day, minute) if minute
      end
      at(first_day, PREFERRED_MINUTE)
    end

    private

    def start_minute(day)
      return nil if @holidays.include?(day)
      return (PREFERRED_MINUTE if FALLBACK_WEEKDAYS.cover?(day.wday)) unless opening_hours?

      intervals = @opening_hours.fetch(day.wday, [])
      return nil if intervals.empty?

      open_at_nine = intervals.find { |_, finish| finish > PREFERRED_MINUTE }
      open_at_nine ? [open_at_nine.first, PREFERRED_MINUTE].max : intervals.first.first
    end

    def opening_hours? = @opening_hours.values.any?(&:any?)

    def at(day, minute)
      @now.time_zone.local(day.year, day.month, day.day, minute / 60, minute % 60)
    end
  end
end
