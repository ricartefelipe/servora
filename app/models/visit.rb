# frozen_string_literal: true

class Visit < TenantRecord
  belongs_to :work_order
  belongs_to :team, optional: true
  belongs_to :scheduled_by, class_name: "Membership", foreign_key: :scheduled_by_membership_id, inverse_of: false
  has_many :allocations, class_name: "TechnicianAllocation", dependent: nil, inverse_of: :visit
  has_many :transitions, -> { order(created_at: :desc) }, class_name: "VisitTransition", dependent: nil, inverse_of: :visit

  enum :status, Visits::States.states.index_by(&:itself), validate: true

  validate :period_is_valid

  scope :upcoming, -> { where(status: %w[scheduled in_progress]).order(:scheduled_start) }
  scope :active_allocations, -> { where(technician_allocations: { status: "active" }) }

  def status_label = Visits::LABELS.fetch(status)
  def duration_minutes = ((scheduled_end - scheduled_start) / 60).round
  def blocked_interval = Scheduling::Interval.for_visit(starts_at: scheduled_start, ends_at: scheduled_end, travel_minutes:)

  private

  def period_is_valid
    return if scheduled_start.blank? || scheduled_end.blank? || scheduled_start < scheduled_end

    errors.add(:scheduled_end, "deve ser posterior ao início")
  end
end
