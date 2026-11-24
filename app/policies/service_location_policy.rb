# frozen_string_literal: true

class ServiceLocationPolicy < ApplicationPolicy
  def create? = can?(:customers_manage)
  def update? = create?
  def archive? = create? && !record.archived?
end
