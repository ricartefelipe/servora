# frozen_string_literal: true

module Seeds
  module DemoActivity
    # The two questions Living asks about each of today's events:
    #
    # * <action>_recorded?(time, params) — was it applied already? Each event
    #   leaves its own mark in what it writes (the instant it wrote, or the
    #   deterministic idempotency key of the operation).
    # * <action>_ready?(params) — is the order still in the state the story
    #   expects before it (actions without a check are always ready)? A
    #   visitor may have added an item still waiting for the customer's
    #   authorization (the order cannot be completed nor billed yet), or put
    #   the technician on another visit (he does not leave for the next one
    #   while it is under way): the event waits, quietly, and the later runs
    #   ask again.
    module LivingChecks
      # Visit states in which a technician is busy with it.
      BUSY = %w[traveling in_progress].freeze

      private

      def living_recorded?(time, action, params) = send(:"#{action}_recorded?", time, params)

      def living_ready?(time, action, params)
        check = :"#{action}_ready?"
        return true unless respond_to?(check, true)

        method(check).arity == 2 ? send(check, time, params) : send(check, params)
      end

      def travel_recorded?(time, params) = visit(params[:order]).travel_started_at == time
      def start_recorded?(time, params) = visit(params[:order]).started_at == time
      def finish_recorded?(time, params) = visit(params[:order]).finished_at == time
      def answer_recorded?(time, params) = checklist_item(params[:order], params[:label]).responded_at == time
      def complete_recorded?(time, params) = order(params[:order]).completed_at == time
      def items_recorded?(time, params) = WorkOrderItem.exists?(work_order_id: id_of(:order, params[:order]), created_at: time)
      def bill_recorded?(time, params) = Receivable.exists?(work_order_id: id_of(:order, params[:order]), created_at: time)
      def schedule_recorded?(_time, params) = resolved?(:visit, params[:order])
      def open_order_recorded?(_time, params) = resolved?(:order, params[:key])
      alias portal_request_recorded? open_order_recorded?

      def report_recorded?(_time, params)
        work_order = order(params[:order])
        work_order.diagnosis == params[:diagnosis] && (params[:solution].nil? || work_order.solution == params[:solution])
      end

      def consume_recorded?(_time, params)
        MaterialConsumption.exists?(idempotency_key: operation_key("consumption", params[:order], params[:sku]))
      end

      def pay_recorded?(_time, params)
        Payment.exists?(idempotency_key: operation_key("payment", params[:receivable], params[:amount]))
      end

      def receive_stock_recorded?(_time, params)
        StockMovement.exists?(idempotency_key: operation_key("receipt", params[:warehouse], params[:sku], params[:reason]))
      end

      def reserve_recorded?(time, params)
        StockReservation.exists?(work_order_id: id_of(:order, params[:order]), created_at: time)
      end

      def wait_parts_recorded?(time, params) = transition_recorded?(params[:order], "waiting_parts", time)
      def wait_customer_recorded?(time, params) = transition_recorded?(params[:order], "waiting_customer", time)
      def triage_recorded?(time, params) = transition_recorded?(params[:order], "approved", time)

      def cancel_visit_recorded?(time, params)
        VisitTransition.exists?(visit_id: visit(params[:order]).id, to_status: "canceled", created_at: time)
      end

      def transition_recorded?(order_key, status, time)
        WorkOrderTransition.exists?(work_order_id: id_of(:order, order_key), to_status: status, created_at: time)
      end

      def travel_ready?(time, params)
        record = visit(params[:order])
        record.status == "scheduled" && technicians_free?(record, time)
      end

      def start_ready?(params) = visit(params[:order]).status == "traveling"
      def finish_ready?(params) = visit(params[:order]).status == "in_progress"
      alias consume_ready? finish_ready?
      alias items_ready? finish_ready?
      def answer_ready?(params) = finish_ready?(params) && checklist_item(params[:order], params[:label]).response.nil?
      def report_ready?(params) = finish_ready?(params) && [nil, params[:diagnosis]].include?(order(params[:order]).diagnosis)
      def reserve_ready?(params) = !order(params[:order]).finished?
      alias wait_parts_ready? reserve_ready?
      def wait_customer_ready?(params) = order(params[:order]).status == "scheduled"
      def cancel_visit_ready?(params) = visit(params[:order]).status == "scheduled"
      def pay_ready?(params) = Receivable.find(id_of(:receivable, params[:receivable])).outstanding?
      def triage_ready?(params) = order(params[:order]).status == "open"
      def schedule_ready?(params) = Scheduling::ScheduleVisit::SCHEDULABLE_STATES.include?(order(params[:order]).status)

      def complete_ready?(params)
        work_order = order(params[:order])
        work_order.status == "in_progress" && visit(params[:order]).status == "completed" && !awaiting_authorization?(work_order)
      end

      def bill_ready?(params)
        work_order = order(params[:order])
        work_order.status == "completed" && !awaiting_authorization?(work_order) &&
          WorkOrderFinancialsQuery.new(work_order).remaining_to_bill.positive?
      end

      def awaiting_authorization?(work_order) = work_order.items.pending_authorization.exists?

      # None of the visit's technicians is on another visit, nor was busy
      # with one at `time` (a visit a visitor started earlier and finished
      # later than the story planned).
      def technicians_free?(record, time)
        others = Visit.joins(:allocations).where.not(id: record.id)
          .where(technician_allocations: { membership_id: record.allocations.map(&:membership_id) })
        others.where(status: BUSY).none? &&
          others.where(started_at: ...time, finished_at: time..).none?
      end

      def checklist_item(order_key, label)
        order(order_key).checklist_items.find { |item| item.label == label } || raise(Unresolved, "checklist item #{label}")
      end
    end
  end
end
