# frozen_string_literal: true

module Sla
  # Applies work order lifecycle events to its SLA clocks. Called explicitly by
  # WorkOrders::Create and WorkOrders::Transition inside their transactions
  # (never from model callbacks).
  #
  # * first response: starts with the request; met when the order reaches a
  #   state that means someone acted on it (scheduled, in progress, waiting,
  #   completed); canceled with the order;
  # * resolution: starts with the request; paused while waiting for the
  #   customer (approval included) or for parts; met/breached on completion;
  #   reopening resumes it with the time already consumed;
  # * targets and the warning threshold are copied from the policy at start.
  class Track
    RESPONDED = %w[scheduled in_progress waiting_parts waiting_customer completed].freeze
    PAUSED = %w[awaiting_approval waiting_parts waiting_customer].freeze

    def initialize(work_order)
      @work_order = work_order
    end

    def start(at: @work_order.requested_at)
      policy = SlaPolicy.find_by(priority: @work_order.priority)
      return [] unless policy

      [["first_response", policy.first_response_minutes], ["resolution", policy.resolution_minutes]].map do |metric, minutes|
        clock = SlaClock.new(organization_id: @work_order.organization_id, work_order: @work_order, metric:,
          target_seconds: minutes * 60, warning_percent: policy.warning_percent,
          business_hours_only: policy.business_hours_only, started_at: at)
        run(clock, at, "started")
      end
    end

    def on_transition(from:, to:, at:)
      clocks = SlaClock.where(work_order_id: @work_order.id).lock.index_by(&:metric)
      return if clocks.empty?

      first_response(clocks["first_response"], to, at)
      resolution(clocks["resolution"], from, to, at)
    end

    private

    def first_response(clock, to, at)
      return unless clock&.running?

      if to == "canceled" then cancel(clock, at)
      elsif RESPONDED.include?(to) then stop(clock, at)
      end
    end

    def resolution(clock, from, to, at)
      return unless clock
      return finish(clock, to, at) if %w[canceled completed].include?(to)
      return pause(clock, at) if PAUSED.include?(to) && clock.running?

      resume_or_reopen(clock, from, at)
    end

    def finish(clock, to, at)
      return if clock.stopped?

      to == "canceled" ? cancel(clock, at) : stop(clock, at)
    end

    def resume_or_reopen(clock, from, at)
      if clock.paused? then run(clock, at, "resumed")
      elsif from == "completed" && %w[met breached].include?(clock.status)
        clock.assign_attributes(segment: clock.segment + 1, stopped_at: nil, warned_at: nil, breach_notified_at: nil,
          breached_at: nil)
        run(clock, at, "reopened")
      end
    end

    def run(clock, at, kind)
      calendar = calendar_for(clock)
      warn_after = (clock.target_seconds * clock.warning_percent / 100) - clock.consumed_seconds
      clock.assign_attributes(status: "running", running_since: at, due_at: calendar.add(at, clock.remaining_seconds),
        warn_at: calendar.add(at, [warn_after, 0].max))
      clock.save!
      log(clock, kind, at, due_at: clock.due_at.iso8601)
      clock
    end

    def pause(clock, at)
      consume(clock, at)
      clock.update!(status: "paused", running_since: nil, due_at: nil, warn_at: nil)
      log(clock, "paused", at, consumed_seconds: clock.consumed_seconds)
    end

    def stop(clock, at)
      consume(clock, at) if clock.running?
      outcome = clock.consumed_seconds <= clock.target_seconds ? "met" : "breached"
      clock.update!(status: outcome, running_since: nil, stopped_at: at,
        breached_at: outcome == "breached" ? (clock.breached_at || clock.due_at || at) : clock.breached_at)
      log(clock, outcome, at, consumed_seconds: clock.consumed_seconds)
    end

    def cancel(clock, at)
      consume(clock, at) if clock.running?
      clock.update!(status: "canceled", running_since: nil, due_at: nil, warn_at: nil, stopped_at: at)
      log(clock, "canceled", at)
    end

    def consume(clock, at)
      clock.consumed_seconds += calendar_for(clock).elapsed(clock.running_since, at)
    end

    def calendar_for(clock)
      @calendars ||= {}
      @calendars[clock.business_hours_only] ||= Calendar.for(organization, business_hours_only: clock.business_hours_only)
    end

    def organization = @organization ||= Organization.find(@work_order.organization_id)

    def log(clock, kind, at, **details)
      SlaClockEvent.create!(organization_id: clock.organization_id, sla_clock: clock, kind:, occurred_at: at, details:)
    end
  end
end
