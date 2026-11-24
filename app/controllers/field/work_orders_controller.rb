# frozen_string_literal: true

module Field
  # Mobile execution view of a work order. Checklist, technical report and
  # time entries are submitted through Field::OperationsController, which also
  # accepts operations queued while offline.
  class WorkOrdersController < TenantController
    layout "field"

    def show
      authorize :field, :show?
      @work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments, :customer, :service_location,
        :checklist_items, :equipment).find(params.expect(:id))
      authorize @work_order, :show?
      @can_execute = policy(@work_order).update_execution?
      @visits = tenant_relation(Visit).where(work_order_id: @work_order.id).upcoming.to_a
      @time_entries = tenant_relation(TimeEntry).where(work_order_id: @work_order.id, membership_id: current_membership.id)
        .order(started_at: :desc).limit(10)
    end
  end
end
