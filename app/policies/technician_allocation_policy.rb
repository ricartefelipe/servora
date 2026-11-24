# frozen_string_literal: true

class TechnicianAllocationPolicy < ApplicationPolicy
  def index? = can?(:schedule_view)
  def create? = can?(:schedule_manage)
  def destroy? = can?(:schedule_manage) && record.kind == "absence"

  class Scope < Scope
    def resolve
      return scope.all if can?(:schedule_manage)

      can?(:schedule_view) ? scope.where(membership_id: membership.id) : scope.none
    end
  end
end
