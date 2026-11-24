# frozen_string_literal: true

# Server-side record of an authenticated browser session (see
# Authentication::SessionTracker). Revoking the row ends the session on the
# next request, regardless of the cookie.
class UserSession < ApplicationRecord
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user

  scope :active, -> { where(revoked_at: nil) }
  scope :recent_first, -> { order(last_seen_at: :desc) }

  def active?
    revoked_at.nil?
  end

  def revoke!(reason:)
    return if revoked_at

    update!(revoked_at: Time.current, revoke_reason: reason)
  end

  def touch_last_seen!(now: Time.current)
    return if last_seen_at && last_seen_at > now - TOUCH_INTERVAL

    # touch skips validations and callbacks on purpose: this runs on every
    # authenticated request and only records activity.
    touch(:last_seen_at, time: now) # rubocop:disable Rails/SkipsModelValidations
  end
end
