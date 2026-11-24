# frozen_string_literal: true

module Visits
  # Cancels a scheduled visit or one on the way (or records a customer
  # no-show) and releases the reservations. A work order left without upcoming
  # visits returns to "approved" (cancel) or "waiting customer" (no-show).
  class Cancel
    class ReasonRequired < Servora::RuleViolation; end

    def initialize(visit:, actor:, reason:, no_show: false)
      @visit = visit
      @actor = actor
      @reason = reason.to_s.strip
      @no_show = no_show
    end

    def call
      raise ReasonRequired, "Informe o motivo." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        @visit.lock!
        work_order = @visit.work_order.lock!
        Transition.apply!(@visit, to: @no_show ? "no_show" : "canceled", actor: @actor, reason: @reason, cancel_reason: @reason)
        Transition.release_allocations!(@visit)
        adjust_work_order(work_order)
        AuditEvent.record!(action: @no_show ? "visit.no_show" : "visit.canceled", auditable: work_order,
          changes: { visit_id: @visit.id, reason: @reason })
        @visit
      end
    end

    private

    def adjust_work_order(work_order)
      return unless work_order.scheduled?
      return if work_order.visits.exists?(status: Visits::OPEN)

      target = @no_show ? "waiting_customer" : "approved"
      WorkOrders::Transition.new(work_order:, to: target, actor: @actor, reason: @reason).call
    end
  end
end
