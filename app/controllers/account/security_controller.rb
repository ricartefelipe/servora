# frozen_string_literal: true

module Account
  class SecurityController < AuthenticatedController
    def show
      @sessions = current_user.user_sessions.active.recent_first.limit(20)
      @current_session_id = Authentication::SessionTracker.current_session_id(warden)
    end
  end
end
