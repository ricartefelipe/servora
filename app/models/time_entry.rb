# frozen_string_literal: true

class TimeEntry < TenantRecord
  belongs_to :work_order
  belongs_to :visit, optional: true
  belongs_to :membership

  validates :source, inclusion: { in: %w[manual field offline] }
  validate :period_is_valid

  private

  def period_is_valid
    return if started_at.blank? || ended_at.blank? || started_at < ended_at

    errors.add(:ended_at, "deve ser posterior ao início")
  end
end
