# frozen_string_literal: true

module Seeds
  module DemoActivity
    # Today's part of a story, applied as its time comes (Demo::AdvanceStoryJob,
    # every 5 minutes in demo mode). The seed records only what has happened at
    # its run instant; #advance applies, at their own instants, the events of
    # today whose time has passed since then, from the same definitions.
    #
    # Each event is applied at most once and leaves its own durable mark in
    # the records it writes, so a run can stop anywhere and the next one
    # resumes: the visit's travel, start and finish instants, the diagnosis,
    # the checklist answer instant, the creation instant of items, bills,
    # reservations, visits, orders and status changes (of the order or of a
    # canceled visit), the completion instant, and the
    # deterministic idempotency keys of consumptions, payments and receipts.
    #
    # Visitors use the demonstration too. Before applying an event, the state
    # its story expects is checked (a visit still on the way before it is
    # started, an order still in progress before it is completed, a bill still
    # open before it is paid...). When a visitor got there first (started,
    # finished or canceled the visit, completed or billed the order, paid the
    # bill), the event and every later event of the same order are skipped,
    # quietly and again on every run; an event that fails anyway is rolled
    # back alone and logged. Nothing is applied when the story was recorded on
    # another day (the visits it scheduled for today are not at today's times),
    # e.g. after midnight and before the daily re-seeding.
    module Living
      include LivingChecks

      # Actions that today's part of a story may use.
      ACTIONS = %i[travel start answer report consume items finish complete bill pay receive_stock reserve schedule
                   wait_parts wait_customer cancel_visit open_order portal_request triage].freeze

      # Applies the events of today up to `now`; returns them as
      # [[instant, action, order key], ...] (empty when nothing was due).
      def advance(now: Time.current)
        Servora::Tenancy.with_organization(@organization_id) do
          @organization = Organization.find(@organization_id)
          next [] unless recorded? && exclusive?

          start_clock(now)
          prepare
          index_creators
          anchored? ? apply_due_events : []
        end
      end

      private

      # One run per organization at a time (the lock ends with the transaction).
      def exclusive?
        ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array(
          ["SELECT pg_try_advisory_xact_lock(hashtext('servora-demo-story'), hashtext(?))", @organization_id]
        ))
      end

      # The story was recorded today: a visit it scheduled for today, before
      # today, is at today's time.
      def anchored?
        midnight = zone.local(@today.year, @today.month, @today.day)
        @creators.any? do |(kind, key), (time, action, params)|
          next false unless kind == :visit && action == :schedule && params[:on] == :today && time < midnight

          resolved?(:visit, key)
        end
      end

      def resolved?(kind, key)
        id_of(kind, key)
        true
      rescue Unresolved
        false
      end

      def due_events
        timeline.select do |time, _, action, _|
          ACTIONS.include?(action) && time <= @now && time.in_time_zone(zone).to_date == @today
        end
      end

      # Applies what is due, in order; once an event of an order is skipped,
      # the later events of that order are skipped too (an event without an
      # order, such as a stock receipt, stands alone).
      def apply_due_events
        blocked = Set.new
        due_events.each_with_object([]) do |(time, _, action, params), applied|
          subject = subject_of(action, params)
          chain = subject || [action, time]
          next if blocked.include?(chain)

          case living_state(time, action, params)
          when :recorded then next
          when :ready then attempt(time, action, params) ? applied << [time, action, subject] : blocked << chain
          else blocked << chain
          end
        end
      end

      # The order an event belongs to (its later events depend on it).
      def subject_of(action, params)
        return params[:order] if params[:order]
        return @creators.dig([:receivable, params[:receivable]], 2, :order) if params[:receivable]

        params[:key] if StoryRecords::CREATES.key?(action)
      end

      # :recorded (already applied), :ready (the state the story expects) or :skip.
      def living_state(time, action, params)
        return :recorded if living_recorded?(time, action, params)

        living_ready?(time, action, params) ? :ready : :skip
      rescue Unresolved, ActiveRecord::RecordNotFound
        :skip
      end

      # Applies one event at its instant, alone in a savepoint. Returns false
      # (and logs) when it fails, which leaves everything as it was.
      def attempt(time, action, params)
        params = params.dup
        actor = params.delete(:by)
        ActiveRecord::Base.transaction(requires_new: true) do
          travel_to(time) { as(actor) { send(action, **params) } }
        end
        true
      rescue StandardError => e
        Rails.logger.warn(Servora::StructuredLog.line(event: "demo.story_event_skipped", organization_id: @organization_id,
          action:, at: time.iso8601, error_class: e.class.name, error: e.message))
        false
      end
    end
  end
end
