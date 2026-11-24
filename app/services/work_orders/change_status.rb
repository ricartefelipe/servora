# frozen_string_literal: true

module WorkOrders
  # Simple operational transitions: start execution, wait for parts or for the
  # customer (both require a reason) and resume.
  class ChangeStatus
    REASON_REQUIRED = %w[waiting_parts waiting_customer].freeze
    ALLOWED_TARGETS = %w[in_progress waiting_parts waiting_customer scheduled approved].freeze

    class ReasonRequired < Servora::RuleViolation; end

    def initialize(work_order:, to:, actor:, reason: nil)
      @work_order = work_order
      @to = to.to_s
      @actor = actor
      @reason = reason.to_s.strip.presence
    end

    def call
      raise Transition::InvalidTransition, "Transição não permitida por esta ação." unless ALLOWED_TARGETS.include?(@to)
      raise ReasonRequired, "Informe o motivo da espera." if REASON_REQUIRED.include?(@to) && @reason.nil?

      ActiveRecord::Base.transaction(requires_new: true) do
        @work_order.lock!
        previous = @work_order.status
        Transition.new(work_order: @work_order, to: @to, actor: @actor, reason: @reason).call
        Outbox::Publisher.publish!(event_type: "work_order.status_changed", aggregate: @work_order,
          payload: { from: previous, to: @to })
        @work_order
      end
    end
  end
end
