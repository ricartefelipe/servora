# frozen_string_literal: true

module WorkOrders
  # PDF of a stored execution report version.
  class ReportsController < TenantController
    include FileDelivery

    def show
      work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(params.expect(:work_order_id))
      authorize work_order, :show?
      report = tenant_relation(WorkOrderReport).where(work_order_id: work_order.id).find(params.expect(:id))
      organization = current_organization.slice("name", "legal_name", "document").transform_values(&:to_s)
      deliver_file(Documents::ExecutionReport.new(report, organization:).render, type: "application/pdf",
        filename: "relatorio-#{work_order.number}-v#{report.version_number}.pdf")
    end
  end
end
