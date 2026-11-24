# frozen_string_literal: true

module WorkOrders
  # Authorized reopening of a completed work order. Previous reports,
  # transitions and execution records are preserved.
  class Reopen
    class ReasonRequired < Servora::RuleViolation; end

    def initialize(work_order:, actor:, reason:)
      @work_order = work_order
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      raise ReasonRequired, "Informe o motivo da reabertura." if @reason.blank?

      ActiveRecord::Base.transaction(requires_new: true) do
        @work_order.lock!
        Transition.new(work_order: @work_order, to: "reopened", actor: @actor, reason: @reason).call
        AuditEvent.record!(action: "work_order.reopened", auditable: @work_order, changes: { reason: @reason })
        Outbox::Publisher.publish!(event_type: "work_order.reopened", aggregate: @work_order,
          dedup_key: "work_order.reopened:#{@work_order.id}:#{@work_order.reopened_count}")
        @work_order
      end
    end
  end
end
