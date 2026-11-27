# frozen_string_literal: true

module Seeds
  module DemoActivity
    module HistoryPlan
      # Priority, lateness and request instant of the routine visits (see
      # HistoryPlan): counters decide them apart, so the deadlines are missed
      # at a steady rate per priority.
      module Profiles
        HIGH_EVERY = 6
        HIGH_LATE_EVERY = 4
        NORMAL_LATE_EVERY = 16
        HIGH_SLOW_EVERY = 3
        NORMAL_SLOW_EVERY = 14
        # The afternoon shift starts at 13:00.
        AFTERNOON = 780

        private

        # What the next repair would be: high priority, late (resolution) and
        # slow (first response), or not. A slow high request is one for a
        # morning visit, made the afternoon before.
        def priority_profile(counts, day, start)
          high = counts[:corrective] % HIGH_EVERY == HIGH_EVERY / 2
          morning = start < AFTERNOON
          { high:, morning:, late: late_repair?(counts, day, high), slow: slow_request?(counts, high, morning) }
        end

        # A late normal repair is requested three business days before its
        # visit, which must be inside the story.
        def late_repair?(counts, day, high)
          return counts[:high] % HIGH_LATE_EVERY == 1 if high

          counts[:normal] % NORMAL_LATE_EVERY == NORMAL_LATE_EVERY / 2 && day - 3 >= -(history_days + 1)
        end

        def slow_request?(counts, high, morning)
          return morning && counts[:high_morning] % HIGH_SLOW_EVERY == 1 if high

          counts[:normal] % NORMAL_SLOW_EVERY == NORMAL_SLOW_EVERY / 2
        end

        # Priority and lateness of the chosen job; advances the counters.
        def profile_of(job, profile, counts, ahead)
          return planned_profile(job, ahead) unless job[:kind] == :corrective

          counts[:corrective] += 1
          counts[profile[:high] ? :high : :normal] += 1
          counts[:high_morning] += 1 if profile[:high] && profile[:morning]
          { priority: profile[:high] ? "high" : "normal", late: late_kind(profile), slow: profile[:slow] }
        end

        # Preventives and visits without a unit opened more than a business
        # day ahead are low priority; they are never late nor slow.
        def planned_profile(job, ahead)
          low = %i[preventive misc].include?(job[:kind]) && ahead > 1
          { priority: low ? "low" : "normal", late: nil, slow: false }
        end

        def late_kind(profile)
          return nil unless profile[:late]

          profile[:high] ? :closing : :request
        end

        # [request day, minutes] of a job planned for a visit on `day` at `start`.
        # Preventives are opened one to three business days ahead, visits
        # without a unit one or two.
        def request_of(job, day, start, profile, seed)
          return repair_request(day, start, profile, seed) if job[:kind] == :corrective

          ahead = hashed("#{seed}:#{job[:customer]}", "ahead", job[:kind] == :preventive ? 3 : 2)
          [[day - 1 - ahead, -(history_days + 1)].max, 600 + (5 * hashed(seed, "opened", 90))]
        end

        # A slow request is made early enough for the answer to come the same
        # day, after its deadline (History#request).
        def repair_request(day, start, profile, seed)
          afternoon = start >= AFTERNOON
          return high_request(day, afternoon, profile, seed) if profile[:high]
          return [day, 495 + (5 * hashed(seed, "opened", 25))] if same_morning?(afternoon, profile, seed)

          [day - (profile[:late] ? 3 : 1), 660 + (5 * hashed(seed, "opened", profile[:slow] ? 7 : 79))]
        end

        # A high-priority repair is requested on the same morning for an
        # afternoon visit, or the afternoon before for a morning one.
        def high_request(day, afternoon, profile, seed)
          return [day, 570 + (5 * hashed(seed, "opened", 25))] if afternoon

          [day - 1, 900 + (5 * hashed(seed, "opened", profile[:slow] ? 7 : 31))]
        end

        # A normal repair is requested on the business day before (three days
        # before when late), or now and then early on the same morning for an
        # afternoon visit.
        def same_morning?(afternoon, profile, seed)
          afternoon && !profile[:late] && !profile[:slow] && hashed(seed, "same_day", 2).zero?
        end

        # Two requests are never recorded at the same minute.
        def opened(planner, (day, minutes))
          minutes += 5 while planner[:opened].include?([day, minutes])
          planner[:opened] << [day, minutes]
          [day, minutes]
        end
      end
    end
  end
end
