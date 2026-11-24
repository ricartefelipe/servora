# frozen_string_literal: true

class Notification < TenantRecord
  belongs_to :recipient, class_name: "Membership", foreign_key: :recipient_membership_id, inverse_of: false

  validates :kind, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :for_recipient, ->(membership) { where(recipient_membership_id: membership.id) }

  def read?
    read_at.present?
  end
end
