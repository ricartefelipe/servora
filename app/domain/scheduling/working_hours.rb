# frozen_string_literal: true

module Scheduling
  # Weekly working hours. Intervals are [start_minute, end_minute) from local
  # midnight; weekday follows Date#wday (0 = Sunday). A period fits when it is
  # entirely inside one interval of its local day (shifts crossing midnight
  # are not supported).
  class WorkingHours
    Slot = Data.define(:weekday, :start_minute, :end_minute)

    def initialize(slots)
      @slots = slots
    end

    def fits?(local_start, local_end)
      return false unless local_start.to_date == local_end.to_date || local_end == local_end.beginning_of_day

      start_minute = (local_start.hour * 60) + local_start.min
      end_minute = local_end == local_end.beginning_of_day ? 1440 : (local_end.hour * 60) + local_end.min
      @slots.any? do |slot|
        slot.weekday == local_start.wday && slot.start_minute <= start_minute && end_minute <= slot.end_minute
      end
    end

    delegate :empty?, to: :@slots

    def for_weekday(weekday)
      @slots.select { |slot| slot.weekday == weekday }.sort_by(&:start_minute)
    end
  end
end
