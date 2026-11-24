# frozen_string_literal: true

# Receivables are visible to financial roles only. Discounts and refunds have
# their own permissions and are never implied by :finance_manage.
class ReceivablePolicy < ApplicationPolicy
  def index? = can?(:finance_view)
  def show? = index?
  def create? = can?(:finance_manage)
  def register_payment? = can?(:finance_manage) && outstanding?
  def discount? = can?(:finance_discount) && outstanding?
  def refund? = can?(:finance_refund)
  def cancel? = can?(:finance_manage) && outstanding?
  def charge? = can?(:finance_manage) && outstanding?
  def invoice? = can?(:finance_manage) && record.is_a?(Receivable) && !record.canceled?

  private

  def outstanding? = record.is_a?(Receivable) && record.outstanding?

  class Scope < Scope
    def resolve
      can?(:finance_view) ? scope.all : scope.none
    end
  end
end
