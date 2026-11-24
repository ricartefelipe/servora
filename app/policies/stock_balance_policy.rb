# frozen_string_literal: true

# Balances and movements are visible wherever the warehouse is visible.
# Moving stock and setting thresholds follow their own permissions; costs and
# stock value only appear with :costs_view.
class StockBalancePolicy < ApplicationPolicy
  def index? = can?(:inventory_view)
  def receive? = can?(:inventory_manage)
  def transfer? = can?(:inventory_manage)
  def adjust? = can?(:inventory_adjust)
  def set_minimum? = can?(:inventory_adjust)
  def view_costs? = can?(:costs_view)

  class Scope < Scope
    def resolve
      scope.where(warehouse_id: WarehousePolicy::Scope.new(context, Warehouse.all).resolve.select(:id))
    end
  end
end
