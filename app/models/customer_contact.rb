# frozen_string_literal: true

# Person at the customer who follows services and, when allowed, approves
# quotes. Portal access requires an e-mail.
class CustomerContact < TenantRecord
  belongs_to :customer

  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :email, presence: { message: "é obrigatório para acesso ao portal" }, if: :portal_enabled?
  validates :phone, :position, length: { maximum: 80 }

  scope :active, -> { where(archived_at: nil) }
  scope :approvers, -> { active.where(can_approve: true) }
  scope :alphabetical, -> { order(:name) }

  def archived? = archived_at.present?
end
