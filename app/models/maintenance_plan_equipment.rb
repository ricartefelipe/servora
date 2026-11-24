# frozen_string_literal: true

class MaintenancePlanEquipment < TenantRecord
  self.table_name = "maintenance_plan_equipment"

  belongs_to :maintenance_plan, inverse_of: :plan_equipment
  belongs_to :equipment
end
