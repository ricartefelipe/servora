# frozen_string_literal: true

class DashboardsController < TenantController
  def show
    authorize :dashboard, :show?
    @overview = Dashboards::Overview.new(membership: current_membership)
    @today = Dashboards::Today.new(membership: current_membership, visits: visible_visits,
      stock_balances: policy_scope(tenant_relation(StockBalance)))
  end

  private

  # Technicians who do not manage the schedule see only the visits they are
  # allocated to; everyone else follows the visit policy scope.
  def visible_visits
    visits = policy_scope(tenant_relation(Visit), policy_scope_class: VisitPolicy::Scope)
    return visits if can?(:schedule_manage) || !can?(:work_orders_execute)

    visits.where(id: tenant_relation(TechnicianAllocation).where(membership_id: current_membership.id, status: "active")
      .select(:visit_id))
  end
end
