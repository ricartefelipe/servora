# frozen_string_literal: true

module WorkOrders
  class Cancel
    class ReasonRequired < Servora::RuleViolation; end

    def initialize(work_order:, actor:, reason:)
      @work_order = work_order
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      raise ReasonRequired, "Informe o motivo do cancelamento." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        @work_order.lock!
        Transition.new(work_order: @work_order, to: "canceled", actor: @actor, reason: @reason).call
        AuditEvent.record!(action: "work_order.canceled", auditable: @work_order, changes: { reason: @reason })
        # Stock reservations and scheduled visits are released by event handlers.
        Outbox::Publisher.publish!(event_type: "work_order.canceled", aggregate: @work_order,
          dedup_key: "work_order.canceled:#{@work_order.id}")
        @work_order
      end
    end
  end
end
