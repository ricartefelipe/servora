# frozen_string_literal: true

# Blocked time of a technician (a visit including travel, or an absence).
# Overlaps of active allocations are rejected by an exclusion constraint.
class TechnicianAllocation < TenantRecord
  belongs_to :membership
  belongs_to :visit, optional: true, inverse_of: :allocations

  validates :kind, inclusion: { in: %w[visit absence] }

  scope :active, -> { where(status: "active") }
  scope :overlapping, ->(interval) { where("period && tstzrange(?, ?, '[)')", interval.starts_at, interval.ends_at) }

  def starts_at = period.begin
  def ends_at = period.end
end
