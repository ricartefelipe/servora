# frozen_string_literal: true

module Evidences
  # Removes an evidence of an open work order. The blob is purged in the same
  # tenant context (synchronously: no background job runs without it).
  class Remove
    def initialize(evidence:, actor:)
      @evidence = evidence
      @actor = actor
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        work_order = WorkOrder.lock.find(@evidence.work_order_id)
        raise Servora::RuleViolation, "Anexos de ordens encerradas são mantidos." if work_order.finished?

        filename = @evidence.file.filename.to_s
        @evidence.file.purge
        @evidence.destroy!
        AuditEvent.record!(action: "work_order.evidence_removed", auditable: work_order, changes: { filename: })
      end
    end
  end
end
