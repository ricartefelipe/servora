# frozen_string_literal: true

class CustomerPolicy < ApplicationPolicy
  def index? = can?(:customers_view)
  def show? = index?
  def create? = can?(:customers_manage)
  def update? = create? && !record_archived?
  def archive? = can?(:customers_manage) && !record_archived?
  def restore? = can?(:customers_manage) && record_archived?

  private

  def record_archived? = record.respond_to?(:archived?) && record.archived?

  class Scope < Scope
    def resolve
      can?(:customers_view) ? scope.all : scope.none
    end
  end
end
