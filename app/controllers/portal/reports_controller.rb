# frozen_string_literal: true

module Portal
  # Execution report PDFs of the customer's own work orders.
  class ReportsController < BaseController
    include FileDelivery

    def show
      work_order = customer_scope(WorkOrder).find(params.expect(:work_order_id))
      report = WorkOrderReport.where(work_order_id: work_order.id).find(params.expect(:id))
      organization = current_portal_organization.slice("name", "legal_name", "document").transform_values(&:to_s)
      deliver_file(Documents::ExecutionReport.new(report, organization:).render, type: "application/pdf",
        filename: "relatorio-#{work_order.number}-v#{report.version_number}.pdf")
    end
  end
end
