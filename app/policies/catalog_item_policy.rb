# frozen_string_literal: true

class CatalogItemPolicy < ApplicationPolicy
  def index? = can?(:catalog_view)
  def show? = index?
  def create? = can?(:catalog_manage)
  def update? = create?
  def view_cost? = can?(:costs_view)

  def permitted_attributes
    attributes = %i[kind name sku description unit unit_price estimated_minutes tracks_inventory active]
    attributes << :unit_cost if view_cost? && can?(:catalog_manage)
    attributes
  end

  class Scope < Scope
    def resolve
      can?(:catalog_view) ? scope.all : scope.none
    end
  end
end
