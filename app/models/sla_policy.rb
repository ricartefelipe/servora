# frozen_string_literal: true

# Targets per work order priority. Clocks copy the targets when they start, so
# later policy changes do not move deadlines already promised.
class SlaPolicy < TenantRecord
  validates :priority, inclusion: { in: WorkOrder::PRIORITIES.keys }, uniqueness: { scope: :organization_id }
  validates :first_response_minutes, :resolution_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :warning_percent, numericality: { only_integer: true, in: 50..95 }
  validate :response_within_resolution

  def priority_label = WorkOrder::PRIORITIES.fetch(priority)

  private

  def response_within_resolution
    return if first_response_minutes.blank? || resolution_minutes.blank? || first_response_minutes <= resolution_minutes

    errors.add(:first_response_minutes, "não pode superar o prazo de resolução")
  end
end
