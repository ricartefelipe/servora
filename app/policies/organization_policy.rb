# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def show? = record == organization
  def update? = show? && can?(:organization_manage)
end
