# frozen_string_literal: true

module EquipmentLifecycle
  module History
    module_function

    def record!(equipment, kind:, actor:, description: nil, **changes)
      equipment.events.create!(organization_id: equipment.organization_id, kind:, description:,
        actor_membership_id: actor&.id, occurred_at: Time.current, **changes)
    end
  end
end
