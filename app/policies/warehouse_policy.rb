# frozen_string_literal: true

# Office roles see every warehouse. Roles whose only stock permission is
# viewing and who do not see every work order (technicians) see just the
# warehouses in their custody. Creating and editing warehouses is a
# structural change reserved to whoever may adjust stock.
class WarehousePolicy < ApplicationPolicy
  def index? = can?(:inventory_view)
  def show? = index?
  def create? = can?(:inventory_adjust)
  def update? = create?

  def permitted_attributes = %i[name kind custodian_membership_id active]

  class Scope < Scope
    def resolve
      return scope.none unless can?(:inventory_view)
      return scope.all if can?(:inventory_manage) || can?(:work_orders_view_all)

      scope.where(custodian_membership_id: membership.id)
    end
  end
end
