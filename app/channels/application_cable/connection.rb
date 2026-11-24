# frozen_string_literal: true

module ApplicationCable
  # WebSocket connections reuse the Warden session cookie. Fetching the user
  # runs the same session-registry check as HTTP requests, so revoked sessions
  # cannot open (or keep) subscriptions.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user(:user) || reject_unauthorized_connection
    end
  end
end
