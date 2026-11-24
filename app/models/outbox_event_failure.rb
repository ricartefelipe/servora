# frozen_string_literal: true

# Append-only history of processing failures (one row per failed attempt).
class OutboxEventFailure < TenantRecord
  belongs_to :outbox_event

  scope :recent_first, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end
end
