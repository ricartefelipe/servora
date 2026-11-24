# frozen_string_literal: true

module WorkOrders
  class ExpensesController < TenantController
    requires_module :finance

    def create
      work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(params.expect(:work_order_id))
      authorize work_order, :record_expense?
      expense = Expense.new(expense_params.merge(organization_id: work_order.organization_id, work_order:,
        recorded_by_membership_id: current_membership.id))
      if expense.save
        AuditEvent.record!(action: "expense.recorded", auditable: work_order,
          changes: { category: expense.category, amount: expense.amount })
        redirect_to work_order_path(work_order, anchor: "financeiro"), notice: "Despesa registrada.", status: :see_other
      else
        redirect_to work_order_path(work_order, anchor: "financeiro"), alert: expense.errors.full_messages.to_sentence,
          status: :see_other
      end
    end

    private

    def expense_params = params.expect(expense: %i[category description amount incurred_on])
  end
end
