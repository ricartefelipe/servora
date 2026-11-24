# frozen_string_literal: true

# API credentials, webhook endpoints and provider webhook tokens.
class IntegrationPolicy < ApplicationPolicy
  def show? = can?(:integrations_manage)
  def manage? = show?
end
