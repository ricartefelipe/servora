# frozen_string_literal: true

# Completion report data frozen at completion time (one per completion).
class WorkOrderReport < TenantRecord
  belongs_to :work_order, inverse_of: :reports

  def readonly? = persisted?
end
