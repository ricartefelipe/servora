# frozen_string_literal: true

module EquipmentLifecycle
  # Deletes equipment registered by mistake. Equipment with service history
  # (work orders, maintenance events) can only be archived; the database also
  # refuses the delete through restrictive foreign keys.
  class Remove
    class InUse < Servora::RuleViolation; end

    def initialize(equipment:)
      @equipment = equipment
    end

    def call
      raise InUse, "Equipamento com histórico de atendimento não pode ser excluído. Arquive-o." if serviced?

      ActiveRecord::Base.transaction(requires_new: true) do
        AuditEvent.record!(action: "equipment.removed", auditable: @equipment, changes: { title: @equipment.title })
        @equipment.destroy!
      end
    rescue ActiveRecord::InvalidForeignKey
      raise InUse, "Equipamento com histórico de atendimento não pode ser excluído. Arquive-o."
    end

    private

    def serviced?
      @equipment.events.exists?(kind: "maintenance")
    end
  end
end
