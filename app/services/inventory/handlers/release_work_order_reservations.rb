# frozen_string_literal: true

module Inventory
  module Handlers
    # work_order.canceled / work_order.completed → release every unconsumed
    # reservation. Consumed material stays consumed (returns are explicit).
    class ReleaseWorkOrderReservations
      def call(event, _context)
        StockReservation.active.where(work_order_id: event.aggregate_id).find_each do |reservation|
          ReleaseReservation.new(reservation:, reason: "Liberação automática (#{event.event_type})").call
        end
      end
    end
  end
end
