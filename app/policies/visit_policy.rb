# frozen_string_literal: true

# Agenda access: dispatch roles see everyone; technicians see their own
# schedule only. Starting and finishing visits belongs to the reserved
# technicians (and to dispatchers).
class VisitPolicy < ApplicationPolicy
  def index? = can?(:schedule_view)
  def create? = can?(:schedule_manage)
  def manage? = can?(:schedule_manage)
  def execute? = manage? || reserved_technician?

  private

  def reserved_technician?
    can?(:work_orders_execute) && record.allocations.any? { |allocation| allocation.membership_id == membership.id }
  end

  class Scope < Scope
    def resolve
      return scope.all if can?(:schedule_manage)
      return scope.where(membership_id: membership.id) if scope.klass <= TechnicianAllocation && can?(:schedule_view)
      return scope.where(id: membership.id) if scope.klass <= Membership && can?(:schedule_view)

      can?(:schedule_view) ? scope.all : scope.none
    end
  end
end
