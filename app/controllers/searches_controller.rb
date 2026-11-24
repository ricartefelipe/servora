# frozen_string_literal: true

# Quick search for the command palette. A group is offered only when the
# member could open the corresponding index page: same policy, same policy
# scope and same subscription module as the sidebar, so the palette never
# reveals more than the menu. Turbo Frame requests receive only the results;
# a regular request renders the same results as a page.
class SearchesController < TenantController
  # The palette queries on every typing pause; this bounds the cost per member.
  rate_limit to: 120, within: 1.minute, by: -> { current_membership&.id || request.remote_ip },
    with: -> { head :too_many_requests }, name: "quick-search"

  # Group => [model, index route used for the module check in NavigationHelper].
  SOURCES = {
    work_orders: [WorkOrder, :work_orders_path],
    customers: [Customer, :customers_path],
    equipment: [Equipment, :equipment_index_path],
    quotes: [Quote, :quotes_path]
  }.freeze

  def show
    # Every member may search; access is decided per group in authorized_scopes.
    skip_authorization
    @term = QuickSearchQuery.normalize(params[:q])
    @groups = QuickSearchQuery.new(term: @term, scopes: authorized_scopes).call
    render layout: false if turbo_frame_request?
  end

  private

  def authorized_scopes
    return {} unless QuickSearchQuery.searchable?(@term)

    SOURCES.each_with_object({}) do |(key, (model, route)), scopes|
      next unless group_available?(model, route)

      scopes[key] = policy_scope(current_organization.public_send(key))
    end
  end

  def group_available?(model, route)
    module_code = NavigationHelper::MODULE_ROUTES[route]
    return false if module_code && !module_enabled?(module_code)

    policy(model).index?
  end
end
