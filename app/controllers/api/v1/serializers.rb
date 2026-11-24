# frozen_string_literal: true

module Api
  module V1
    # JSON representations of the public API. Internal costs, notes and
    # credentials are never exposed.
    module Serializers
      module_function

      def customer(record)
        { id: record.id, kind: record.kind, name: record.name, trade_name: record.trade_name,
          document: record.document,
          email: record.email, phone: record.phone, archived: record.archived_at.present?,
          updated_at: time(record.updated_at) }
      end

      def equipment(record)
        { id: record.id, customer_id: record.customer_id, service_location_id: record.service_location_id,
          equipment_type: record.equipment_type, manufacturer: record.manufacturer, model: record.model,
          serial_number: record.serial_number, operational_status: record.operational_status,
          updated_at: time(record.updated_at) }
      end

      def work_order(record)
        { id: record.id, number: record.number, title: record.title, status: record.status, priority: record.priority,
          origin: record.origin, customer_id: record.customer_id, service_location_id: record.service_location_id,
          requested_at: time(record.requested_at), completed_at: time(record.completed_at), updated_at: time(record.updated_at) }
      end

      def receivable(record)
        { id: record.id, number: record.number, work_order_id: record.work_order_id, customer_id: record.customer_id,
          status: record.status, due_on: record.due_on&.iso8601, amount: money(record.amount),
          discount_amount: money(record.discount_amount), balance: money(record.balance), updated_at: time(record.updated_at) }
      end

      def time(value) = value&.utc&.iso8601
      def money(value) = Pricing::Amount.money(value).to_s("F")
    end
  end
end
