# frozen_string_literal: true

module Outbox
  # Authorized manual reprocessing of a dead event. The attempt counter starts
  # over; failure history is kept.
  class Reprocess
    class NotReprocessable < Servora::RuleViolation; end

    def initialize(event:)
      @event = event
    end

    def call
      @event.with_lock do
        raise NotReprocessable, "Somente eventos com falha definitiva podem ser reprocessados." unless @event.dead?

        @event.update!(status: "pending", attempts: 0, available_at: Time.current, last_error: nil)
      end
      AuditEvent.record!(action: "outbox.reprocessed", auditable: @event, changes: { event_type: @event.event_type })
      ActiveRecord.after_all_transactions_commit { Outbox::Kick.call }
      @event
    end
  end
end
