# frozen_string_literal: true

class PaymentIntegrationPolicy < ApplicationPolicy
  def show? = can?(:integrations_manage)
  def update? = show?
end
