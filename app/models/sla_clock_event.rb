# frozen_string_literal: true

# Append-only history of a clock.
class SlaClockEvent < TenantRecord
  belongs_to :sla_clock, inverse_of: :events

  def readonly? = persisted?
end
