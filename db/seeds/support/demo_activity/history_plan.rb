# frozen_string_literal: true

require "zlib"
require_relative "history_plan/profiles"
require_relative "history_plan/choice"
require_relative "history_plan/written_work"
require_relative "history_plan/windows"

module Seeds
  module DemoActivity
    # Agenda of the routine work (History): on every business day of the
    # story before today, each technician's shifts take the visits that the
    # customers' units call for that day (RoutineJobs, within the rules of
    # RoutineBook), around the hand-written visits of the story (EVENTS) and
    # with the organization's travel buffer between them. A visit lasts what
    # its work takes; a day takes a few routine visits (DAY_VISITS), in a
    # mixed order of shifts. Times and choices come from deterministic hashes,
    # so every load of the same day gives the same agenda without a visible
    # fixed pattern.
    #
    # Priority and lateness are decided apart (Profiles): every HIGH_EVERY-th
    # repair is high priority (preventives never are, and are opened by the
    # office as "Manutenção preventiva"); every HIGH_LATE_EVERY-th high one is
    # closed by the office only on the next business day, and every
    # NORMAL_LATE_EVERY-th normal repair waited a few days for a free slot, so
    # both miss their resolution deadline. Independently, now and then the
    # office answers a request after its first response deadline
    # (HIGH_SLOW_EVERY-th high request for a morning visit,
    # NORMAL_SLOW_EVERY-th normal one).
    module HistoryPlan
      include Profiles
      include Choice
      include WrittenWork
      include Windows

      TECHNICIANS = %i[diego eduarda fabio].freeze
      CREWS = { all: TECHNICIANS, electrical: %i[diego fabio], refrigeration: %i[diego eduarda] }.freeze
      # Working shifts (minutes of the day) and the buffer between two visits
      # of one technician (the organization's travel_buffer_minutes).
      SHIFTS = [[480, 720], [780, 1080]].freeze
      TRAVEL = 30
      SHORTEST_VISIT = 60
      # Most visits of a technician in [morning, afternoon] on a day.
      LAYOUTS = [[1, 2], [2, 1], [2, 2], [1, 1], [2, 2]].freeze
      # Routine visits of a day: DAY_VISITS plus up to DAY_SPREAD - 1 more,
      # so the work spreads over the story instead of crowding some days.
      DAY_VISITS = 3
      DAY_SPREAD = 3
      # A day with fewer routine visits than this is a quiet one (Choice).
      QUIET_DAY = 3

      # A visit of the plan. late: :closing (the office completes it on the
      # next business day) or :request (requested three business days before
      # the visit); requested: [request day, minutes of the day]; slow: the
      # office answered after the first response deadline.
      Routine = Data.define(:key, :index, :job, :day, :from, :to, :technician, :priority, :late, :slow, :requested) do
        def seed = key.to_s
      end

      # Where a visit may go: a business day of the story, a technician, the
      # minute it would start, the minutes left in its window and the seed of
      # its hashes.
      Slot = Data.define(:day, :technician, :start, :room, :seed)

      private

      # [Routine, ...] of the business days before today, planned from the
      # last one backwards: the rules limit how often a customer calls, so
      # the recent days, the ones people look at first, get the work.
      def history_plan
        @history_plan ||= begin
          planner = { book: routine_book, counts: Hash.new(0), opened: Set.new,
                      specials: self.class::HISTORY_SPECIALS.dup,
                      quotes: self.class::HISTORY_QUOTES.each_with_index.to_a, routines: [] }
          (-history_days..-1).reverse_each { |day| plan_day(day, planner) }
          planner[:routines]
        end
      end

      # A quiet day takes, on a second pass, the work Choice keeps for one.
      def plan_day(day, planner)
        planned = planner[:routines].size
        fill_slots(day, planner)
        return if planner[:routines].size - planned >= QUIET_DAY

        planner[:early] = true
        fill_slots(day, planner)
      ensure
        planner[:early] = false
      end

      # The free windows of the day's shifts take the work in a mixed order,
      # so the requests of the day go to mornings and afternoons alike.
      def fill_slots(day, planner)
        date = calendar_day(day).iso8601
        planned = planner[:routines].count { |routine| routine.day == day }
        planner[:room] = DAY_VISITS + hashed(date, "visits", DAY_SPREAD) - planned
        day_windows(day, planner).sort_by { |technician, (from, _), _| hashed("#{date}:#{technician}:#{from}", "order", 10_000) }
          .each { |technician, window, quota| fill(window, quota, day, technician, planner) }
      end

      # Up to `quota` visits in a window, one after the other; the last one
      # may start later in the window, so free time is not always at the end.
      def fill((from, to), quota, day, technician, planner)
        seed = "#{calendar_day(day).iso8601}:#{technician}:#{from}"
        start = from + (5 * hashed(seed, "start", 4))
        quota.times do |position|
          break unless planner[:room].positive?

          slot = Slot.new(day:, technician:, start:, room: to - start, seed: "#{seed}:#{position}")
          routine = plan_visit(slot, planner, last: position == quota - 1)
          break unless routine

          start = routine.to + TRAVEL + (5 * hashed(seed, "gap#{position}", 4))
        end
      end

      def plan_visit(slot, planner, last:)
        profile = priority_profile(planner[:counts], slot.day, slot.start)
        job, requested = choose(slot, planner, profile)
        return nil unless job

        length = visit_length(job, slot)
        start = visit_start(slot, length, last)
        planner[:book].record(job, calendar_day(requested.first))
        add_routine(planner, job:, day: slot.day, technician: slot.technician, from: start, to: start + length, requested:,
          **profile_of(job, profile, planner[:counts], slot.day - requested.first))
      end

      # What the work takes, give or take ten minutes, within the window.
      def visit_length(job, slot)
        [((job[:minutes] + (5 * (hashed(slot.seed, "length", 5) - 2))) / 5 * 5), slot.room].min
      end

      # The last visit of a window may start a little later in it.
      def visit_start(slot, length, last)
        return slot.start unless last

        slot.start + (5 * hashed(slot.seed, "offset", [((slot.room - length) / 5) + 1, 19].min))
      end

      def add_routine(planner, **attributes)
        index = planner[:routines].size
        planner[:room] -= 1
        Routine.new(key: :"h#{index}", index:, **attributes).tap { |routine| planner[:routines] << routine }
      end

      # Deterministic integer in 0...range for `seed` and `salt`.
      def hashed(seed, salt, range) = Zlib.crc32("#{seed}:#{salt}") % range

      def minutes(time) = time.split(":").map { |part| Integer(part, 10) }.then { |hour, minute| (hour * 60) + minute }
      def clock(minutes) = format("%<hour>02d:%<minute>02d", hour: minutes / 60, minute: minutes % 60)
    end
  end
end
