# frozen_string_literal: true

module EquipmentLifecycle
  class Register
    def initialize(organization:, attributes:, actor:)
      @organization = organization
      @attributes = attributes
      @actor = actor
    end

    def call
      equipment = @organization.equipment.new(@attributes)
      ActiveRecord::Base.transaction(requires_new: true) do
        equipment.save!
        History.record!(equipment, kind: "registered", actor: @actor, to_customer_id: equipment.customer_id,
          to_location_id: equipment.service_location_id, to_status: equipment.operational_status)
        AuditEvent.record!(action: "equipment.registered", auditable: equipment, changes: { title: equipment.title })
      end
      equipment
    end
  end
end
