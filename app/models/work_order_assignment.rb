# frozen_string_literal: true

class WorkOrderAssignment < TenantRecord
  belongs_to :work_order, inverse_of: :assignments
  belongs_to :membership

  validates :role, inclusion: { in: %w[lead technician] }
end
