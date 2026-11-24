# frozen_string_literal: true

module EquipmentLifecycle
  class ChangeStatus
    def initialize(equipment:, status:, actor:, reason: nil)
      @equipment = equipment
      @status = status
      @actor = actor
      @reason = reason
    end

    def call
      return @equipment if @equipment.operational_status == @status

      ActiveRecord::Base.transaction(requires_new: true) do
        previous = @equipment.operational_status
        @equipment.update!(operational_status: @status)
        History.record!(@equipment, kind: "status_changed", actor: @actor, description: @reason,
          from_status: previous, to_status: @status)
        AuditEvent.record!(action: "equipment.status_changed", auditable: @equipment, changes: { from: previous, to: @status })
      end
      @equipment
    end
  end
end
