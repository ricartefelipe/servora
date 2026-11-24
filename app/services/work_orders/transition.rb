# frozen_string_literal: true

module WorkOrders
  # Applies a state change validated by WorkOrders::States and records it in
  # work_order_transitions. Callers hold the work order row lock.
  class Transition
    class InvalidTransition < Servora::RuleViolation; end

    def initialize(work_order:, to:, actor:, reason: nil, at: Time.current)
      @work_order = work_order
      @to = to.to_s
      @actor = actor
      @reason = reason
      @at = at
    end

    def call
      from = @work_order.status
      unless WorkOrders::States.allowed?(from, @to)
        raise InvalidTransition,
          "Não é possível passar de #{WorkOrders::LABELS[from]} para #{WorkOrders::LABELS.fetch(@to, @to)}."
      end

      @work_order.update!(timestamp_attributes.merge(status: @to))
      @work_order.transitions.create!(organization_id: @work_order.organization_id, from_status: from, to_status: @to,
        reason: @reason, actor_membership_id: @actor&.id, actor_label: @actor&.user&.name || Current.actor_label)
      @work_order
    end

    private

    def timestamp_attributes
      case @to
      when "in_progress" then { started_at: @work_order.started_at || @at }
      when "completed" then { completed_at: @at }
      when "canceled" then { canceled_at: @at, cancel_reason: @reason }
      when "reopened" then { completed_at: nil, reopened_count: @work_order.reopened_count + 1 }
      else {}
      end
    end
  end
end
