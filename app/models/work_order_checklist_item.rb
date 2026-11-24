# frozen_string_literal: true

# Checklist copied from the service type into the work order (later changes to
# the service type do not alter it). lock_version detects concurrent answers,
# including offline drafts synchronized later.
class WorkOrderChecklistItem < TenantRecord
  belongs_to :work_order, inverse_of: :checklist_items
  belongs_to :responded_by, class_name: "Membership", foreign_key: :responded_by_membership_id, optional: true,
    inverse_of: false

  validates :response, length: { maximum: 1000 }
  validate :response_matches_kind

  def answered? = response.to_s.strip.present?

  private

  def response_matches_kind
    return if response.blank?

    case response_kind
    when "check" then errors.add(:response, "deve ser sim ou não") unless %w[sim nao].include?(response)
    when "number" then errors.add(:response, "deve ser um número") unless response.match?(/\A-?\d+([.,]\d+)?\z/)
    end
  end
end
