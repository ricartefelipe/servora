# frozen_string_literal: true

class MembershipPolicy < ApplicationPolicy
  def index? = can?(:members_view)
  def show? = index?

  # Owners can only be managed by owners; nobody changes their own role or
  # deactivates themselves (that would allow locking an organization out).
  def update?
    can?(:members_manage) && !self_record? && (!record.owner? || membership.owner?)
  end

  def deactivate? = update? && record.active?
  def reactivate? = update? && record.deactivated?

  def assignable_roles
    roles = Authorization::Permissions::ROLES
    membership.owner? ? roles : roles - %w[owner]
  end

  def view_costs? = can?(:costs_view)

  def permitted_attributes
    attributes = %i[role job_title phone]
    attributes << :hourly_cost if view_costs?
    attributes
  end

  private

  def self_record? = record.id == membership.id

  class Scope < Scope
    def resolve
      can?(:members_view) ? scope.all : scope.where(id: membership.id)
    end
  end
end
