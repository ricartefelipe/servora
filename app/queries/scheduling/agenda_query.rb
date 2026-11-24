# frozen_string_literal: true

module Scheduling
  # Day/week agenda: technicians with their allocations (visits and absences)
  # in the requested range, plus timeline geometry in 15-minute slots.
  class AgendaQuery
    DAY_START_HOUR = 6
    DAY_END_HOUR = 22
    SLOT_MINUTES = 15
    SLOTS = ((DAY_END_HOUR - DAY_START_HOUR) * 60) / SLOT_MINUTES

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
        technicians = @technicians_scope.includes(:user).ordered.to_a
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

    private

    def allocations
      first = @days.first.in_time_zone.beginning_of_day
      last = @days.last.in_time_zone.end_of_day
      @allocations_scope.active.where("period && tstzrange(?, ?, '[)')", first, last)
        .includes(visit: { work_order: %i[customer service_location] }).to_a
    end

    def block(allocation, day)
      window_start = day.in_time_zone.change(hour: DAY_START_HOUR)
      window_end = day.in_time_zone.change(hour: DAY_END_HOUR)
      starts = [allocation.starts_at, window_start].max
      ends = [allocation.ends_at, window_end].min
      return nil unless starts < ends

      first_slot = ((starts - window_start) / 60 / SLOT_MINUTES).floor
      last_slot = ((ends - window_start) / 60 / SLOT_MINUTES).ceil
      Block.new(allocation:, column_start: first_slot + 1, column_span: [last_slot - first_slot, 1].max)
    end
  end
end
