# frozen_string_literal: true

module Scheduling
  # Day/week agenda: technicians with their allocations (visits and absences)
  # in the requested range, plus timeline geometry in 15-minute slots.
  #
  # The day timeline shows whole hours within DAY_START_HOUR..DAY_END_HOUR,
  # fitted to the shown technicians' working hours and the day's allocations
  # (#hours), so blocks get as much width as the day allows.
  class AgendaQuery
    DAY_START_HOUR = 6
    DAY_END_HOUR = 22
    MIN_HOURS = 8
    SLOT_MINUTES = 15
    SLOTS_PER_HOUR = 60 / SLOT_MINUTES

    Block = Data.define(:allocation, :column_start, :column_span) do
      delegate :visit, to: :allocation
      def absence? = allocation.kind == "absence"
    end

    Row = Data.define(:membership, :allocations)

    attr_reader :days

    def initialize(technicians_scope:, allocations_scope:, date:, mode:, membership_id: nil)
      @technicians_scope = technicians_scope
      @allocations_scope = allocations_scope
      @date = date
      @mode = mode == "semana" ? "semana" : "dia"
      @membership_id = membership_id
      @days = @mode == "semana" ? date.all_week.to_a : [date]
    end

    def week? = @mode == "semana"

    def rows
      @rows ||= begin
        technicians = @technicians_scope.includes(:user, :work_schedules).ordered.to_a
        technicians = technicians.select { |m| m.id == @membership_id } if @membership_id
        grouped = allocations.group_by(&:membership_id)
        technicians.map { |membership| Row.new(membership:, allocations: grouped.fetch(membership.id, [])) }
      end
    end

    def blocks_for(row, day)
      row.allocations.filter_map { |allocation| block(allocation, day) }
    end

    def allocations_on(row, day)
      range = day.in_time_zone.all_day
      row.allocations.select { |a| a.starts_at < range.end && a.ends_at > range.begin }.sort_by(&:starts_at)
    end

    # Hours of the day timeline (a range of whole hours, end excluded): from
    # the earliest to the latest minute of the shown technicians' working hours
    # and allocations on the day, within DAY_START_HOUR..DAY_END_HOUR and at
    # least MIN_HOURS long. With neither, the whole range.
    def hours
      @hours ||= begin
        day = @days.first
        minutes = rows.flat_map { |row| busy_minutes(row, day) }
        minutes.empty? ? (DAY_START_HOUR...DAY_END_HOUR) : fitted_hours(minutes.min, minutes.max)
      end
    end

    def slots = hours.size * SLOTS_PER_HOUR
    def window_start(day = @days.first) = day.in_time_zone.change(hour: hours.first)
    def window_end(day = @days.first) = day.in_time_zone.change(hour: hours.end)

    private

    def allocations
      first = @days.first.in_time_zone.beginning_of_day
      last = @days.last.in_time_zone.end_of_day
      @allocations_scope.active.where("period && tstzrange(?, ?, '[)')", first, last)
        .includes(visit: { work_order: %i[customer service_location] }).to_a
    end

    def block(allocation, day)
      from = window_start(day)
      starts = [allocation.starts_at, from].max
      ends = [allocation.ends_at, window_end(day)].min
      return nil unless starts < ends

      first_slot = ((starts - from) / 60 / SLOT_MINUTES).floor
      last_slot = ((ends - from) / 60 / SLOT_MINUTES).ceil
      Block.new(allocation:, column_start: first_slot + 1, column_span: [last_slot - first_slot, 1].max)
    end

    # Minutes from local midnight (0..1440) bounding the member's working hours
    # and allocations on the day.
    def busy_minutes(row, day)
      midnight = day.in_time_zone.beginning_of_day
      worked = row.membership.working_hours.for_weekday(day.wday).flat_map { |slot| [slot.start_minute, slot.end_minute] }
      allocated = allocations_on(row, day).flat_map do |allocation|
        [allocation.starts_at, allocation.ends_at].map { |time| ((time - midnight) / 60).clamp(0, 1440) }
      end
      worked + allocated
    end

    def fitted_hours(first_minute, last_minute)
      first = (first_minute / 60).floor.clamp(DAY_START_HOUR, DAY_END_HOUR - MIN_HOURS)
      last = (last_minute / 60.0).ceil.clamp(first + MIN_HOURS, DAY_END_HOUR)
      first...last
    end
  end
end
