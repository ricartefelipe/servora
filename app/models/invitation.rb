# frozen_string_literal: true

# Single-use invitation to join an organization. Only the SHA-256 digest of the
# token is stored; the clear token exists only in the e-mail.
class Invitation < TenantRecord
  VALIDITY = 7.days

  belongs_to :invited_by, class_name: "Membership", foreign_key: :invited_by_membership_id, inverse_of: false
  belongs_to :accepted_user, class_name: "User", optional: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }
  validates :role, inclusion: { in: Authorization::Permissions::ROLES }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def state(now: Time.current)
    return :accepted if accepted_at
    return :revoked if revoked_at
    return :expired if expires_at <= now

    :pending
  end

  def usable?(now: Time.current)
    state(now:) == :pending
  end

  def role_label
    Membership::ROLE_LABELS.fetch(role)
  end
end
