# frozen_string_literal: true

class ContractPolicy < ApplicationPolicy
  def index? = can?(:contracts_view)
  def show? = index?
  def create? = can?(:contracts_manage)
  def update? = create? && record.is_a?(Contract) && !record.ended?
  def change_status? = update?
  def add_plan? = can?(:preventive_manage) && record.is_a?(Contract) && !record.ended?

  class Scope < Scope
    def resolve
      can?(:contracts_view) ? scope.all : scope.none
    end
  end
end
