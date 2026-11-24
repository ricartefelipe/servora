# frozen_string_literal: true

module Outbox
  # Exponential backoff for failed events: 15s, 30s, 1min, 2min… capped at 1h.
  # A deterministic jitter (0–9% derived from the event id) spreads retries of
  # events that failed together without making tests nondeterministic.
  module RetrySchedule
    BASE_SECONDS = 15
    MAX_SECONDS = 3_600

    module_function

    def delay_for(attempt:, key:)
      raise ArgumentError, "attempt must be positive" unless attempt.to_i.positive?

      base = [BASE_SECONDS * (2**(attempt.to_i - 1)), MAX_SECONDS].min
      jitter = base * (key.to_s.sum % 10) / 100
      base + jitter
    end

    def exhausted?(attempt:, max_attempts:)
      attempt.to_i >= max_attempts.to_i
    end
  end
end
