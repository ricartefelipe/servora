# frozen_string_literal: true

module Outbox
  # Records an event inside the caller's transaction.
  #
  # Must run inside the tenant context of the aggregate's organization (RLS
  # rejects anything else). With a dedup_key, publishing the same logical event
  # twice is a no-op. After the outermost transaction commits, a dispatch job is
  # enqueued as a latency optimization only: if that enqueue fails or the
  # process dies first, the recurring dispatcher still finds the event.
  class Publisher
    DEDUP_INDEX = :index_outbox_events_on_organization_id_and_dedup_key

    def self.publish!(...) = new.publish!(...)

    def publish!(event_type:, aggregate:, payload: {}, dedup_key: nil)
      attributes = {
        organization_id: aggregate.organization_id, event_type:, aggregate_type: aggregate.class.name,
        aggregate_id: aggregate.id, payload: payload.as_json, dedup_key:, request_id: Current.request_id,
        available_at: Time.current
      }
      event_id = insert(attributes) # rubocop:disable Rails/SkipsModelValidations -- private method named insert
      schedule_dispatch if event_id
      event_id
    end

    private

    # INSERT … ON CONFLICT DO NOTHING (dedup) without model callbacks.
    # rubocop:disable-next Rails/SkipsModelValidations
    def insert(attributes)
      result =
        if attributes[:dedup_key]
          OutboxEvent.insert(attributes, unique_by: DEDUP_INDEX, returning: :id)
        else
          OutboxEvent.insert(attributes, returning: :id)
        end
      result.rows.first&.first
    end

    def schedule_dispatch
      ActiveRecord.after_all_transactions_commit { Outbox::Kick.call }
    end
  end
end
