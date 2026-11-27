# frozen_string_literal: true

module Seeds
  module DemoActivity
    module HistoryPlan
      # The free time of the technicians on a day of the routine plan (see
      # HistoryPlan): their shifts minus the hand-written and the routine
      # visits already planned, with the travel buffer after each visit.
      module Windows
        private

        # [technician, window, most visits] of every free window of the day.
        def day_windows(day, planner)
          date = calendar_day(day)
          HistoryPlan::TECHNICIANS.flat_map do |technician|
            layout = HistoryPlan::LAYOUTS[hashed("#{date.iso8601}:#{technician}", "layout", HistoryPlan::LAYOUTS.size)]
            busy = busy_minutes(date, technician) + planned_minutes(planner, day, technician)
            HistoryPlan::SHIFTS.each_with_index.flat_map do |shift, position|
              windows = free_windows(shift, busy)
              windows.map { |window| [technician, window, windows.size == 1 ? layout[position] : 1] }
            end
          end
        end

        # [[from, to + travel], ...] of the routine visits already planned.
        def planned_minutes(planner, day, technician)
          planner[:routines].filter_map do |routine|
            [routine.from, routine.to + TRAVEL] if routine.day == day && routine.technician == technician
          end
        end

        # Parts of a shift that a visit (plus the travel buffer after it) can use.
        def free_windows(shift, busy)
          windows = [shift]
          busy.each do |taken_from, taken_to|
            windows = windows.flat_map do |from, to|
              next [[from, to]] if taken_to <= from || taken_from >= to + TRAVEL

              [[from, taken_from - TRAVEL], [taken_to, to]]
            end
          end
          windows.select { |from, to| to - from >= SHORTEST_VISIT }
        end
      end
    end
  end
end
