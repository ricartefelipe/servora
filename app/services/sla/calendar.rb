# frozen_string_literal: true

module Sla
  # Builds the business calendar of the current organization (RLS scoped).
  module Calendar
    module_function

    def for(organization, business_hours_only: true)
      return BusinessCalendar.continuous(organization.time_zone) unless business_hours_only

      intervals = BusinessHour.order(:weekday, :start_minute).pluck(:weekday, :start_minute, :end_minute)
        .group_by(&:first).transform_values { |rows| rows.map { |_, start, finish| [start, finish] } }
      calendar = BusinessCalendar.new(intervals:, holidays: Holiday.pluck(:date), zone: organization.time_zone)
      # Without configured hours a deadline cannot be computed in business time.
      calendar.business_hours? ? calendar : BusinessCalendar.continuous(organization.time_zone)
    end
  end
end
