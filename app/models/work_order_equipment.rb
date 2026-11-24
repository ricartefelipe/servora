# frozen_string_literal: true

class WorkOrderEquipment < TenantRecord
  self.table_name = "work_order_equipment"

  belongs_to :work_order, inverse_of: :work_order_equipment
  belongs_to :equipment
end
