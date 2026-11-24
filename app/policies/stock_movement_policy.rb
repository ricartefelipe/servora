# frozen_string_literal: true

class StockMovementPolicy < ApplicationPolicy
  def index? = can?(:inventory_view)
  def view_costs? = can?(:costs_view)

  class Scope < StockBalancePolicy::Scope; end
end
