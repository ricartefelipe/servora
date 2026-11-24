# frozen_string_literal: true

module WorkOrders
  # Formal completion (office side). Requires the checklist, diagnosis and
  # solution, no visit in progress and no pending additional authorization.
  # Each completion stores a new report version; reopening never erases them.
  class Complete
    class RequirementsMissing < Servora::RuleViolation; end

    def initialize(work_order:, actor:)
      @work_order = work_order
      @actor = actor
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @work_order.lock!
        ensure_requirements!
        report = store_report
        Transition.new(work_order: @work_order, to: "completed", actor: @actor).call
        AuditEvent.record!(action: "work_order.completed", auditable: @work_order,
          changes: { report_version: report.version_number })
        Outbox::Publisher.publish!(event_type: "work_order.completed", aggregate: @work_order,
          dedup_key: "work_order.completed:#{@work_order.id}:#{report.version_number}")
        @work_order
      end
    end

    private

    def ensure_requirements!
      missing = WorkOrders::CompletionRequirements.missing(
        checklist: @work_order.checklist_items.map do |item|
          CompletionRequirements::Checklist.new(item.label, item.required, item.response)
        end,
        diagnosis: @work_order.diagnosis, solution: @work_order.solution,
        visits_in_progress: visits_in_progress, pending_authorizations: @work_order.items.pending_authorization.count
      )
      raise RequirementsMissing, "Para concluir: #{missing.join("; ")}." if missing.any?
    end

    # Visits are introduced by the scheduling module; until a work order has
    # visits there is nothing in progress to wait for.
    def visits_in_progress = 0

    def store_report
      data = ReportBuilder.new(@work_order).call
      version = (@work_order.reports.maximum(:version_number) || 0) + 1
      @work_order.reports.create!(organization_id: @work_order.organization_id, version_number: version, data:,
        content_digest: Quotes::ContentDigest.call(data), generated_by_membership_id: @actor&.id)
    end
  end
end
