# frozen_string_literal: true

module Seeds
  module DemoActivity
    module HistoryPlan
      # The job a slot of the agenda takes (see HistoryPlan): a special job,
      # an approved quote, or what the units and customers call for that day
      # within the rules of RoutineBook. On a quiet day the office brings
      # preventives forward (up to a quarter of their interval, at least
      # PREVENTIVE_FORWARD days), takes the repairs of units that would call
      # a little later (twice the chance) and a business may have one request
      # more than usual.
      module Choice
        # Chance (1 in n per request day) that a unit calls for a repair.
        FAULT_ODDS = { "company" => 6, "individual" => 15 }.freeze
        # Chance (1 in n per day) of a visit without a unit, once per customer.
        MISC_ODDS = 30
        # A preventive is done up to PREVENTIVE_EARLY days before or
        # PREVENTIVE_LATE days after its due date.
        PREVENTIVE_EARLY = 6
        PREVENTIVE_LATE = 2
        PREVENTIVE_FORWARD = 7
        PREVENTIVE_EPOCH = Date.new(2026, 1, 1)
        # An approved quote is executed within QUOTE_WINDOW business days of
        # its target day.
        QUOTE_WINDOW = 8

        private

        # [job, [request day, minutes]] for the slot, or nil when nothing is due.
        def choose(slot, planner, profile)
          take_special(slot, planner, profile) || take_quote(slot, planner) || take_due(slot, planner, profile)
        end

        def take_due(slot, planner, profile)
          requests = Hash.new { |hash, job| hash[job] = request_of(job, slot.day, slot.start, profile, slot.seed) }
            .compare_by_identity
          job = due_jobs(slot, planner, requests)
            .min_by { |candidate| hashed("#{slot.seed}:#{candidate[:customer]}:#{candidate[:title]}", "pick", 100_000) }
          job && [job, opened(planner, requests[job])]
        end

        def due_jobs(slot, planner, requests)
          date = calendar_day(slot.day)
          routine_pool.select do |job|
            requested = calendar_day(requests[job].first)
            fits?(job, slot) && due?(job, date, requested, early: planner[:early]) &&
              planner[:book].allows?(job, requested, quiet: planner[:early])
          end
        end

        # A special job is done once, at the first slot that suits it in the
        # first half of the story.
        def take_special(slot, planner, profile)
          job = slot.day <= -(history_days / 2) && planner[:specials].find { |special| fits?(special, slot) }
          return nil unless job

          requested = request_of(job, slot.day, HistoryPlan::SHIFTS.first.first, profile, slot.seed)
          return nil unless planner[:book].allows?(job, calendar_day(requested.first))

          planner[:specials].delete(job)
          [job, opened(planner, requested)]
        end

        # Quotes approved by the customer are executed spread over the story
        # (the first one a week in, so it was sent inside it), each one at a
        # slot that suits it near its target day.
        def take_quote(slot, planner)
          requested = [slot.day - 1, 660 + (5 * hashed(slot.seed, "opened", 61))]
          date = calendar_day(requested.first)
          entry = planner[:quotes].find do |job, position|
            slot.day.between?(*quote_window(position)) && fits?(job, slot) &&
              planner[:book].allows?({ **job[:book], agreed: true }, date)
          end
          return nil unless entry

          planner[:quotes].delete(entry)
          [entry.first, opened(planner, requested)]
        end

        def quote_window(position)
          target = -history_days + 6 + ((history_days - 8) * position / [self.class::HISTORY_QUOTES.size, 1].max)
          [target, target + QUOTE_WINDOW]
        end

        def fits?(job, slot)
          HistoryPlan::CREWS.fetch(job[:crew] || :all).include?(slot.technician) && job[:minutes] + 10 <= slot.room
        end

        # A repair when the unit calls for it on the request day; a preventive
        # near its due date; a visit without a unit now and then.
        def due?(job, date, request_date, early: false)
          case job[:kind]
          when :corrective then unit_calls?(job, request_date, early)
          when :preventive then preventive_due?(job, date, early:)
          else hashed("#{job[:customer]}:#{job[:template]}:#{date.iso8601}", "misc", MISC_ODDS).zero?
          end
        end

        def unit_calls?(job, request_date, early)
          odds = FAULT_ODDS.fetch(job[:customer_kind])
          odds /= 2 if early
          job[:equipment].all? { |serial| hashed("#{serial}:#{request_date.iso8601}", "fault", odds).zero? }
        end

        # Near its due date (well before it on a quiet day), unless that date
        # came before the story (the visit of that period happened before it).
        def preventive_due?(job, date, early:)
          interval = RoutineBook.interval_days(job[:interval])
          phase = hashed("#{job[:customer]}:#{job[:location]}:#{job[:interval]}", "phase", interval)
          offset = (date - PREVENTIVE_EPOCH - phase) % interval
          ahead = early ? [PREVENTIVE_FORWARD, interval / 4].max : PREVENTIVE_EARLY
          due = if offset <= PREVENTIVE_LATE then date - offset
                elsif interval - offset <= ahead then date + (interval - offset)
                end
          !due.nil? && due >= calendar_day(-history_days)
        end
      end
    end
  end
end
