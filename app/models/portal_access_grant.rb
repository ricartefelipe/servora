# frozen_string_literal: true

# Single-use, expiring access link for a customer contact. Only the digest is
# stored; the clear token is generated at e-mail delivery time.
class PortalAccessGrant < TenantRecord
  VALIDITY = 72.hours

  belongs_to :contact, class_name: "CustomerContact"
  belongs_to :quote, optional: true

  validates :purpose, inclusion: { in: %w[quote_review portal] }

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  def self.generate_token = SecureRandom.urlsafe_base64(32)

  def usable?(now: Time.current)
    used_at.nil? && revoked_at.nil? && expires_at > now
  end
end
