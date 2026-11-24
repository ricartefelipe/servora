# frozen_string_literal: true

# Global identity. Organization-specific data (role, status, labor cost) lives
# in Membership.
class User < ApplicationRecord
  devise :two_factor_authenticatable, :two_factor_backupable,
    :registerable, :recoverable, :validatable, :confirmable, :lockable, :trackable, :timeoutable,
    otp_backup_code_length: 10, otp_number_of_backup_codes: 10

  has_many :memberships, dependent: :restrict_with_exception
  has_many :user_sessions, dependent: :delete_all

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true, length: { maximum: 120 }

  def active_memberships
    memberships.active.includes(:organization).order(:created_at)
  end

  def mfa_enabled?
    otp_required_for_login?
  end

  def display_initials
    name.to_s.split.first(2).pluck(0).join.upcase.presence || "?"
  end

  # Devise sends e-mails through the job queue so request latency does not
  # depend on the SMTP server.
  def send_devise_notification(notification, *)
    devise_mailer.send(notification, self, *).deliver_later
  end
end
