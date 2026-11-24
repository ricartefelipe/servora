# frozen_string_literal: true

class EquipmentPolicy < ApplicationPolicy
  def index? = can?(:equipment_view)
  def show? = index?
  def create? = can?(:equipment_manage)
  def update? = create? && !record_archived?
  def relocate? = update?
  def change_status? = update?
  def archive? = can?(:equipment_manage) && !record_archived?
  def restore? = can?(:equipment_manage) && record_archived?
  def destroy? = can?(:equipment_manage)

  private

  def record_archived? = record.respond_to?(:archived?) && record.archived?

  # Office roles see the whole asset base. Technicians only see equipment
  # linked to work they are assigned to (scope extended with work orders).
  class Scope < Scope
    def resolve
      return scope.all if can?(:customers_view)
      return scope.none unless can?(:equipment_view)

      assigned_to_technician
    end

    private

    def assigned_to_technician
      scope.none
    end
  end
end
