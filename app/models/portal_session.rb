# frozen_string_literal: true

# Restricted session of a customer contact in the portal.
class PortalSession < TenantRecord
  DURATION = 12.hours

  belongs_to :contact, class_name: "CustomerContact"
  belongs_to :grant, class_name: "PortalAccessGrant"

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def active?(now: Time.current) = revoked_at.nil? && expires_at > now
end
