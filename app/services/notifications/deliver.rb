# frozen_string_literal: true

module Notifications
  # Creates in-app notifications idempotently (one per recipient and event)
  # and schedules the real-time broadcast after the transaction commits.
  class Deliver
    def initialize(event:, context:)
      @event = event
      @context = context
    end

    def call(recipients:, kind:, title:, body: nil, path: nil)
      rows = recipients.map do |recipient|
        { organization_id: @event.organization_id, recipient_membership_id: recipient.id, outbox_event_id: @event.id,
          kind:, title: title.first(200), body: body&.first(500), path: }
      end
      # INSERT … ON CONFLICT DO NOTHING is what makes repeated handling idempotent.
      inserted = Notification.insert_all(rows, unique_by: :index_notifications_dedup, returning: :id).rows.flatten # rubocop:disable Rails/SkipsModelValidations
      @context.enqueue(Notifications::BroadcastJob, @event.organization_id, inserted) if inserted.any?
      inserted
    end
  end
end
