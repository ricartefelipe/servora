# frozen_string_literal: true

class DashboardsController < TenantController
  def show
    authorize :dashboard, :show?
    @overview = Dashboards::Overview.new(membership: current_membership)
  end
end
