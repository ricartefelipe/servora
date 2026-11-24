# frozen_string_literal: true

module Webhooks
  # Minimal, stable payloads for outbound webhooks: identifiers and states,
  # never internal costs or notes. Receivers fetch details through the API.
  module Payload
    module_function

    def for(event)
      record = event.aggregate_type.constantize.find(event.aggregate_id)
      { "id" => event.id, "type" => event.event_type, "created_at" => event.created_at.utc.iso8601,
        "data" => data(record) }
    end

    def data(record)
      case record
      when WorkOrder
        { "work_order" => { "id" => record.id, "number" => record.number, "status" => record.status,
                            "customer_id" => record.customer_id, "priority" => record.priority } }
      when Quote
        { "quote" => { "id" => record.id, "number" => record.number, "status" => record.status,
                       "customer_id" => record.customer_id } }
      else
        { "id" => record.id }
      end
    end
  end
end
