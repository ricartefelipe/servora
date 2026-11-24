# frozen_string_literal: true

class MaintenancePlanPolicy < ApplicationPolicy
  def show? = can?(:contracts_view)
  def update? = can?(:preventive_manage) && record.active?
  def generate? = update?
end
