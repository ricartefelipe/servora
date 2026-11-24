# frozen_string_literal: true

class ServiceTypePolicy < ApplicationPolicy
  def index? = can?(:work_orders_manage) || can?(:catalog_manage)
  def create? = index?
  def update? = index?

  class Scope < Scope
    def resolve
      can?(:work_orders_manage) || can?(:catalog_manage) ? scope.all : scope.none
    end
  end
end
