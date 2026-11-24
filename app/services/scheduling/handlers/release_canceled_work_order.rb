# frozen_string_literal: true

module Scheduling
  module Handlers
    # work_order.canceled → cancel its upcoming visits and free the technicians.
    # Idempotent: visits already canceled are skipped.
    class ReleaseCanceledWorkOrder
      def call(event, _context)
        Visit.where(work_order_id: event.aggregate_id, status: "scheduled").find_each do |visit|
          Visits::Transition.apply!(visit, to: "canceled", actor: nil, reason: "Ordem de serviço cancelada",
            cancel_reason: "Ordem de serviço cancelada")
          Visits::Transition.release_allocations!(visit)
        end
      end
    end
  end
end
