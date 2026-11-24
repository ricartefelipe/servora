# frozen_string_literal: true

module EquipmentLifecycle
  # Moves equipment to another location. When the location belongs to another
  # customer the move is an ownership transfer. History keeps both ends.
  # Optimistic locking (lock_version) rejects moves based on a stale screen.
  class Relocate
    class SameLocation < Servora::RuleViolation; end

    def initialize(equipment:, location:, actor:, reason: nil, expected_version: nil)
      @equipment = equipment
      @location = location
      @actor = actor
      @reason = reason
      @expected_version = expected_version
    end

    def call
      raise SameLocation, "O equipamento já está neste local." if @location.id == @equipment.service_location_id

      ActiveRecord::Base.transaction(requires_new: true) do
        from_customer = @equipment.customer_id
        from_location = @equipment.service_location_id
        @equipment.lock_version = @expected_version if @expected_version
        @equipment.update!(customer_id: @location.customer_id, service_location: @location)
        record_history(from_customer, from_location)
      end
      @equipment
    end

    private

    def record_history(from_customer, from_location)
      kind = from_customer == @equipment.customer_id ? "relocated" : "ownership_transferred"
      History.record!(@equipment, kind:, actor: @actor, description: @reason,
        from_customer_id: from_customer, to_customer_id: @equipment.customer_id,
        from_location_id: from_location, to_location_id: @equipment.service_location_id)
      AuditEvent.record!(action: "equipment.#{kind}", auditable: @equipment,
        changes: { from_location_id: from_location, to_location_id: @equipment.service_location_id })
    end
  end
end
