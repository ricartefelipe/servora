# frozen_string_literal: true

# Generated occurrence of a plan, identified by (plan, sequence) and linked to
# the work order created for it.
class MaintenanceOccurrence < TenantRecord
  belongs_to :maintenance_plan, inverse_of: :occurrences
  belongs_to :work_order, inverse_of: :maintenance_occurrence
end
