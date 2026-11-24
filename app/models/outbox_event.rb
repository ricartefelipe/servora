# frozen_string_literal: true

# Event recorded in the same transaction as the business change that caused
# it. Payloads carry identifiers only; handlers reload data under RLS.
class OutboxEvent < TenantRecord
  STATUSES = %w[pending processing processed dead].freeze

  has_many :failures, class_name: "OutboxEventFailure", dependent: :restrict_with_exception

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :event_type, :aggregate_type, :aggregate_id, presence: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :attention, -> { where(status: "dead").or(where(status: "pending").where("attempts > 0")) }

  def lease_held_by?(worker_id, now: Time.current)
    processing? && locked_by == worker_id && locked_until.present? && locked_until > now
  end
end
