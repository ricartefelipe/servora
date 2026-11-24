# frozen_string_literal: true

class CustomerContactPolicy < ApplicationPolicy
  def create? = can?(:customers_manage)
  def update? = create?
  def archive? = create? && !record.archived?
end
