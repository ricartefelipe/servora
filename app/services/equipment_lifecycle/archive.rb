# frozen_string_literal: true

module EquipmentLifecycle
  # Archive/restore keep the record and its history; removal is only possible
  # for equipment that was never serviced (see Remove).
  class Archive
    def initialize(equipment:, actor:, restore: false)
      @equipment = equipment
      @actor = actor
      @restore = restore
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @equipment.update!(archived_at: @restore ? nil : Time.current)
        kind = @restore ? "restored" : "archived"
        History.record!(@equipment, kind:, actor: @actor)
        AuditEvent.record!(action: "equipment.#{kind}", auditable: @equipment)
      end
      @equipment
    end
  end
end
