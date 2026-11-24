# frozen_string_literal: true

module Outbox
  # Processes one claimed event. Returns :processed, :retried, :dead or
  # :skipped (lease lost to another worker).
  class Processing
    def initialize(event_id:, organization_id:, worker_id:, clock: -> { Time.current })
      @event_id = event_id
      @organization_id = organization_id
      @worker_id = worker_id
      @clock = clock
    end

    def call
      context = Outbox::Context.new
      event = handle(context)
      return :skipped unless event

      context.jobs.each { |job_class, arguments| job_class.perform_later(*arguments) }
      acknowledge ? record(:processed, event) : :skipped
    rescue StandardError => e
      fail_attempt(e)
    end

    private

    def handle(context)
      Servora::Tenancy.with_organization(@organization_id) do
        event = OutboxEvent.lock.find_by(id: @event_id)
        next nil unless event&.lease_held_by?(@worker_id, now: @clock.call)

        Current.set(request_id: event.request_id) do
          Outbox::Registry.handlers_for(event.event_type).each { |handler| handler.new.call(event, context) }
        end
        event
      end
    end

    def acknowledge
      Servora::Tenancy.with_organization(@organization_id) do
        # Conditional UPDATE: only acknowledges while the lease is still ours.
        # rubocop:disable-next Rails/SkipsModelValidations
        OutboxEvent.where(id: @event_id, status: "processing", locked_by: @worker_id)
          .update_all(status: "processed", processed_at: @clock.call, locked_by: nil, locked_until: nil,
            last_error: nil, updated_at: @clock.call)
          .positive?
      end
    end

    def fail_attempt(error)
      Servora::Tenancy.with_organization(@organization_id) do
        event = OutboxEvent.lock.find_by(id: @event_id)
        next :skipped unless event && event.locked_by == @worker_id

        transient = Outbox::FailureClassifier.transient?(error)
        dead = !transient || Outbox::RetrySchedule.exhausted?(attempt: event.attempts, max_attempts: event.max_attempts)
        event.failures.create!(organization_id: @organization_id, attempt: event.attempts, transient:,
          error_class: error.class.name, error_message: error.message.to_s.first(500))
        event.update!(failure_attributes(event, error, dead))
        record(dead ? :dead : :retried, event)
      end
    end

    def failure_attributes(event, error, dead)
      delay = Outbox::RetrySchedule.delay_for(attempt: event.attempts, key: event.id)
      {
        status: dead ? "dead" : "pending", locked_by: nil, locked_until: nil,
        available_at: dead ? event.available_at : @clock.call + delay,
        last_error: "#{error.class.name}: #{error.message}".first(500)
      }
    end

    def record(outcome, event)
      Servora::Metrics.increment(:outbox_events_processed_total, { event_type: event.event_type, outcome: outcome.to_s })
      Rails.logger.info(event: "outbox.#{outcome}", outbox_event_id: event.id, event_type: event.event_type,
        attempts: event.attempts, request_id: event.request_id)
      outcome
    end
  end
end
