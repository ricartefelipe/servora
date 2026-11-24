# frozen_string_literal: true

module Authentication
  # Keeps one UserSession row per authenticated browser session.
  #
  # Called from Warden hooks (config/initializers/warden_sessions.rb):
  # * start  - after a successful sign in;
  # * active_session? - on every request that fetches the user from the cookie; a missing
  #            or revoked row ends the session immediately;
  # * finish - on logout.
  class SessionTracker
    SESSION_KEY = "servora.user_session_id"

    def self.current_session_id(warden, scope: :user)
      new(warden:, scope:).session_data[SESSION_KEY]
    end

    def initialize(warden:, scope:)
      @warden = warden
      @scope = scope
    end

    def start(user)
      request = @warden.request
      record = user.user_sessions.create!(
        ip_address: request.remote_ip,
        user_agent: request.user_agent.to_s.first(255),
        last_seen_at: Time.current
      )
      session_data[SESSION_KEY] = record.id
      record
    end

    def active_session?(user)
      record = current_record(user)
      return false unless record&.active?

      record.touch_last_seen!
      true
    end

    def finish(user, reason: "logout")
      current_record(user)&.revoke!(reason:)
    end

    # Reads the scope's session hash directly: warden.session(scope) would
    # re-run authentication (and these hooks) while a logout is in progress.
    def session_data
      @warden.raw_session["warden.user.#{@scope}.session"] ||= {}
    end

    private

    def current_record(user)
      id = session_data[SESSION_KEY]
      id.present? ? user.user_sessions.find_by(id:) : nil
    end
  end
end
