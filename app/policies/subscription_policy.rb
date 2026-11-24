# frozen_string_literal: true

class SubscriptionPolicy < ApplicationPolicy
  def show? = can?(:subscription_manage)
  def update? = show?
end
