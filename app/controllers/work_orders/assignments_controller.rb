# frozen_string_literal: true

module WorkOrders
  class AssignmentsController < TenantController
    before_action :load_work_order

    def create
      authorize @work_order, :assign?
      membership = tenant_relation(Membership).find(params.expect(assignment: [:membership_id])[:membership_id])
      WorkOrders::Assign.new(work_order: @work_order, membership:).call
      redirect_to work_order_path(@work_order), notice: "Técnico atribuído.", status: :see_other
    rescue Servora::RuleViolation => e
      redirect_to work_order_path(@work_order), alert: e.message, status: :see_other
    end

    def destroy
      authorize @work_order, :assign?
      assignment = tenant_relation(WorkOrderAssignment).where(work_order_id: @work_order.id).find(params.expect(:id))
      assignment.destroy!
      AuditEvent.record!(action: "work_order.unassigned", auditable: @work_order,
        changes: { membership_id: assignment.membership_id })
      redirect_to work_order_path(@work_order), notice: "Técnico removido da ordem.", status: :see_other
    end

    private

    def load_work_order
      @work_order = policy_scope(tenant_relation(WorkOrder)).find(params.expect(:work_order_id))
    end
  end
end
