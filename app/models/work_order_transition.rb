# frozen_string_literal: true

class WorkOrderTransition < TenantRecord
  belongs_to :work_order, inverse_of: :transitions

  def readonly? = persisted?
  def from_label = from_status && WorkOrders::LABELS.fetch(from_status)
  def to_label = WorkOrders::LABELS.fetch(to_status)
end
