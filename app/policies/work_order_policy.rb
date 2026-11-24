# frozen_string_literal: true

# Office roles see every work order; technicians see only work orders they are
# assigned to. Formal completion is an office action (technicians request it
# from the field area); prices and costs follow their own permissions.
class WorkOrderPolicy < ApplicationPolicy
  def index? = can?(:work_orders_view_all) || can?(:work_orders_execute)
  def show? = can?(:work_orders_view_all) || executor?
  def create? = can?(:work_orders_manage)
  def update_execution? = !record.finished? && (can?(:work_orders_manage) || executor?)
  def change_status? = update_execution?
  def complete? = can?(:work_orders_manage) && !record.finished?
  def cancel? = can?(:work_orders_cancel) && !record.finished?
  def reopen? = can?(:work_orders_reopen) && record.completed?
  def add_item? = update_execution?
  def decide_item? = can?(:additional_services_authorize) && !record.finished?
  def assign? = can?(:work_orders_manage) && !record.finished?
  # Materials: office stock roles reserve, release and return; whoever
  # executes the order may also record consumption.
  def reserve_material? = can?(:inventory_manage) && !record.finished?
  def release_material? = can?(:inventory_manage)
  def consume_material? = !record.finished? && (can?(:inventory_manage) || executor?)
  def return_material? = can?(:inventory_manage) && !record.canceled?
  def view_materials? = can?(:inventory_view) && show?
  # Finance on the work order: billing and expenses are financial actions;
  # margins require the internal cost permission.
  def view_finance? = can?(:finance_view) && show?
  def bill? = can?(:finance_manage) && !record.canceled?
  def record_expense? = can?(:finance_manage) && !record.canceled?
  def add_evidence? = update_execution?
  def remove_evidence? = can?(:work_orders_manage) && !record.finished?
  def view_prices? = can?(:quotes_view) || can?(:finance_view)
  def view_costs? = can?(:costs_view)

  private

  def executor?
    can?(:work_orders_execute) && record.assignments.any? { |assignment| assignment.membership_id == membership.id }
  end

  class Scope < Scope
    def resolve
      return scope.all if can?(:work_orders_view_all)
      return scope.none unless can?(:work_orders_execute)

      scope.where(id: WorkOrderAssignment.where(membership_id: membership.id).select(:work_order_id))
    end
  end
end
