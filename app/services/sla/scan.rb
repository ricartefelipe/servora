# frozen_string_literal: true

module Sla
  # Finds running clocks that entered the warning window or passed their
  # deadline and publishes one alert per clock and segment.
  #
  # Deduplication does not rely on the scan being single: the clock row is
  # claimed with UPDATE … WHERE warned_at IS NULL (or breach_notified_at IS
  # NULL) and only the claimer publishes; the outbox dedup key repeats the
  # guarantee.
  class Scan
    BATCH = 200

    def initialize(now: Time.current)
      @now = now
    end

    def call
      { warned: claim(:warned_at, :warn_at, "warned", "sla.warning"),
        breached: claim(:breach_notified_at, :due_at, "breached", "sla.breached") }
    end

    private

    def claim(flag, deadline, kind, event_type)
      candidates = SlaClock.running.where(flag => nil).where(deadline => ..@now).order(deadline).limit(BATCH).pluck(:id)
      candidates.count { |id| claim_one(id, flag, kind, event_type) }
    end

    def claim_one(id, flag, kind, event_type)
      ActiveRecord::Base.transaction(requires_new: true) do
        changes = { flag => @now, updated_at: @now }
        changes[:breached_at] = @now if flag == :breach_notified_at
        claimed = SlaClock.where(id:, status: "running", flag => nil).update_all(changes) # rubocop:disable Rails/SkipsModelValidations -- conditional claim is the deduplication
        next false if claimed.zero?

        clock = SlaClock.find(id)
        SlaClockEvent.create!(organization_id: clock.organization_id, sla_clock: clock, kind:, occurred_at: @now,
          details: { due_at: clock.due_at.iso8601 })
        Outbox::Publisher.publish!(event_type:, aggregate: clock, payload: { metric: clock.metric },
          dedup_key: "#{event_type}:#{clock.id}:#{clock.segment}")
        true
      end
    end
  end
end
