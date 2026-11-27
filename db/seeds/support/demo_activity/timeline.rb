# frozen_string_literal: true

require "active_support/testing/time_helpers"

module Seeds
  module DemoActivity
    # Replays the history of one organization through its use cases.
    #
    # A story is a list of events [day, "HH:MM", action, params]. Events run in
    # chronological order (ties keep their written order), each one with the
    # clock moved to its own instant, so timestamps, SLA clocks, ledgers,
    # audit and outbox events are exactly what the application records when
    # people act at those moments. Days are relative to the run date in the
    # organization's time zone:
    #
    #   :today, :yesterday       calendar days
    #   Integer n                n business days from today (negative = before)
    #   [:days, n]               n calendar days from today
    #   Date                     that date
    #   :start                   first day of the story (StoryClock.history_days + 1 business days ago)
    #   :at_risk                 instant computed by the story (time is "+MM")
    #
    # Only what has already happened is recorded: events dated after the run
    # instant are skipped, so a visit scheduled for 10:00 is still "Agendada"
    # when the story is loaded at 03:55 and done when it is loaded at 15:00.
    # The result depends only on the run instant. The events of today skipped
    # this way are applied later, as their time comes, by Demo::AdvanceStoryJob
    # (see Living), from these same definitions.
    #
    # Inside each event the effects of the background workers happen at the
    # same instant, as they would in production: the organization's outbox is
    # dispatched right away (notifications, portal links, stock releases) and
    # the SLA scan runs at the deadlines reached since the previous event (on
    # the 5-minute cadence of config/recurring.yml) and at the end of each day,
    # so warnings precede breaches. The daily quote expiry runs at 00:15. Jobs
    # requested by the handlers (e-mails) are enqueued after the story commits.
    #
    # The whole story runs inside one tenant transaction: it is stored
    # completely or not at all. A receipt with a deterministic idempotency key
    # (MARKER_RECEIPT; the stock ledger is append-only) marks it as recorded.
    class Timeline
      include ActiveSupport::Testing::TimeHelpers
      include OfficeActions
      include QuoteActions
      include FieldActions
      include StoryRecords
      include Living

      SCAN_INTERVAL = 300
      DAILY_ROUTINES = [["00:15", :expire_quotes], ["23:55", :end_of_day]].freeze
      # Real-time broadcasts are pointless for notifications of the past.
      SKIPPED_JOBS = %w[Notifications::BroadcastJob].freeze
      NEXT_DEADLINE_SQL = "LEAST(min(warn_at) FILTER (WHERE warned_at IS NULL), " \
                          "min(due_at) FILTER (WHERE breach_notified_at IS NULL))"
      # The story's calendar: the hours and holidays the seed loads, fixed.
      # A visitor who adds a holiday (or changes the business hours) changes
      # the SLA deadlines from then on, as in production, but not the days and
      # instants of the story, so the events of today are still found and
      # applied (Living).
      HOLIDAY_DATES = HOLIDAYS.keys.to_set { |date| Date.iso8601(date) }.freeze
      # Statements after which the replay dispatches the outbox or looks for
      # the next SLA deadline again (see #track_writes).
      OUTBOX_WRITE = /\AINSERT INTO "outbox_events"/
      SLA_WRITE = /\A(?:INSERT INTO|UPDATE) "sla_clocks"/

      def initialize(organization_key, history_days: StoryClock.history_days)
        raise ArgumentError, "the story needs at least 6 business days of history" if history_days < 6

        @organization_id = ORGANIZATIONS.fetch(organization_key)[:id]
        @history_days = history_days
        @ids = Hash.new { |hash, kind| hash[kind] = {} }
        @members = {}
        @jobs = []
      end

      # Returns true when the story was recorded, false when it already existed.
      def call
        recorded = Servora::Tenancy.with_organization(@organization_id) do
          @organization = Organization.find(@organization_id)
          next false if recorded?

          record
          true
        end
        enqueue_jobs if recorded
        recorded
      end

      private

      attr_reader :organization, :history_days

      def record
        start_clock(Time.current)
        prepare
        track_writes do
          replay
          catch_up(@now)
        end
        Sla::Scan.new(now: @now).call
        dispatch
        settle_notifications
        raise "story #{self.class.name} has no marker receipt" unless recorded?
      end

      def start_clock(now)
        @now = now.change(usec: 0)
        @today = @now.in_time_zone(zone).to_date
        @holidays = HOLIDAY_DATES
      end

      def recorded?
        StockMovement.exists?(idempotency_key: operation_key("receipt", *self.class::MARKER_RECEIPT))
      end

      # Hook for stories that compute instants before replaying.
      def prepare; end

      # Every event and daily routine up to the run instant, in order.
      def replay
        timeline.each do |time, _, action, params|
          next if time > @now

          catch_up(time)
          params = params.dup
          actor = params.delete(:by)
          travel_to(time) do
            as(actor) { send(action, **params) }
            dispatch
          end
        end
      end

      def timeline
        @timeline ||= begin
          events = self.class::EVENTS + extra_events
          timed = events.each_with_index.map do |(day, time, action, params), index|
            [event_instant(day, time, action), index, action, params]
          end
          routines = (calendar_day(:start)..@today).flat_map do |date|
            DAILY_ROUTINES.map { |time, action| [instant(date, time), -1, action, {}] }
          end
          (timed + routines).sort_by { |time, index, _, _| [time, index] }
        end
      end

      # Hook for generated events (see History).
      def extra_events = []

      def expire_quotes
        Quotes::ExpireDue.new(organization:).call
      end

      def end_of_day
        Sla::Scan.new.call
      end

      # SLA scans at every warning or deadline reached up to `limit`.
      def catch_up(limit)
        while (at = next_scan(limit))
          travel_to(at) do
            Sla::Scan.new.call
            dispatch
          end
        end
      end

      def next_scan(limit)
        @next_deadline = nil if @writes.nil? || @writes.delete?(:sla)
        @next_deadline ||= [SlaClock.running.pick(Arel.sql(NEXT_DEADLINE_SQL))]
        first = @next_deadline.first
        return nil if first.nil? || first > limit

        [Time.zone.at((first.to_f / SCAN_INTERVAL).ceil * SCAN_INTERVAL), limit].min
      end

      # While the story is replayed, the outbox is read only after an event was
      # published and the next SLA deadline only after a clock changed: with
      # thousands of events this saves two queries per event, and the result
      # is the same as reading them every time.
      def track_writes
        @writes = Set[:outbox, :sla]
        thread = Thread.current
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          next unless Thread.current == thread

          sql = payload[:sql]
          @writes << :outbox if OUTBOX_WRITE.match?(sql)
          @writes << :sla if SLA_WRITE.match?(sql)
        end
        yield
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
        @writes = nil
      end

      # Synchronous version of Outbox::Processing for this organization: the
      # same handlers, at the current (story) instant. Events published by the
      # handlers themselves are handled by the next dispatch.
      def dispatch
        return if @writes && !@writes.delete?(:outbox)

        OutboxEvent.where(status: "pending", available_at: ..Time.current).order(:available_at, :id).each do |event|
          handle(event)
        end
      end

      # Rows written with insert_all carry the database clock (the real
      # instant), so the event and its notifications get the story instant.
      def handle(event)
        context = Outbox::Context.new
        Current.set(request_id: event.request_id) do
          Outbox::Registry.handlers_for(event.event_type).each { |handler| handler.new.call(event, context) }
        end
        now = Time.current
        # rubocop:disable Rails/SkipsModelValidations -- acknowledgement as in Outbox::Processing, and timestamps
        OutboxEvent.where(id: event.id).update_all(status: "processed", processed_at: now, attempts: event.attempts + 1,
          created_at: event.available_at, updated_at: now)
        Notification.where(outbox_event_id: event.id).update_all(created_at: now, updated_at: now)
        # rubocop:enable Rails/SkipsModelValidations
        @jobs.concat(context.jobs.reject { |job_class, _| SKIPPED_JOBS.include?(job_class.name) })
      end

      def enqueue_jobs
        @jobs.uniq.each { |job_class, arguments| job_class.perform_later(*arguments) }
      end

      # People read what was notified before the last business day.
      def settle_notifications
        cutoff = business_day(-1).in_time_zone(zone)
        Notification.where(read_at: nil, created_at: ...cutoff)
          .update_all("read_at = created_at + interval '1 hour'") # rubocop:disable Rails/SkipsModelValidations -- as if opened by each recipient
      end

      def as(key, &)
        return yield if key.nil?

        membership = member(key)
        Current.set(organization:, membership:, user: membership.user, &)
      end

      def zone = organization.zone
      def today = Time.current.in_time_zone(zone).to_date

      # Payments are received (and settled) on business days: one written for
      # a weekend or holiday (today, when the story is loaded on one) happens
      # on the next business day, at the same time.
      def event_instant(day, time, action)
        at = instant(day, time)
        return at unless action == :pay

        date = at.in_time_zone(zone).to_date
        moved = settlement_day(date)
        moved == date ? at : instant(moved, time)
      end

      def instant(day, time)
        return @risk_instant + (Integer(time.delete_prefix("+")) * 60) if day == :at_risk

        date = calendar_day(day)
        hour, minute = time.split(":").map { |part| Integer(part, 10) }
        zone.local(date.year, date.month, date.day, hour, minute)
      end

      def calendar_day(day)
        case day
        when :today then @today
        when :yesterday then @today - 1
        when :start then business_day(-(history_days + 1))
        when Integer then business_day(day)
        when Date then day
        when Array then @today + day.last
        else raise ArgumentError, "unknown day #{day.inspect}"
        end
      end

      # n business days from `from` (Monday to Friday, holidays excluded).
      def business_day(offset, from: @today)
        step = offset.negative? ? -1 : 1
        date = from
        offset.abs.times do
          date += step
          date += step until business_day?(date)
        end
        date
      end

      def business_day?(date) = date.on_weekday? && @holidays.exclude?(date)

      # The SLA calendar the seed configured (business hours and holidays),
      # for the instants the story computes from a deadline.
      def story_calendar(business_hours_only:)
        return Sla::BusinessCalendar.continuous(zone) unless business_hours_only

        Sla::BusinessCalendar.new(intervals: (1..5).index_with { SHIFTS_SLA }, holidays: @holidays, zone:)
      end

      # Due dates and settlements fall on business days: `date` or the next one.
      def settlement_day(date)
        date += 1 until business_day?(date)
        date
      end

      def member(key)
        @members[key] ||= Membership.includes(:user, :work_schedules).joins(:user)
          .find_by!(organization_id: @organization_id, users: { email: self.class::PEOPLE.fetch(key) })
      end
    end
  end
end
