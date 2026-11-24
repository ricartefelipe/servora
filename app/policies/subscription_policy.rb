# frozen_string_literal: true

class SubscriptionPolicy < ApplicationPolicy
  def show? = can?(:subscription_manage)
  def update? = show?
  def simulate_invoice_payment? = update?
end
