# frozen_string_literal: true

module Account
  class SessionsController < AuthenticatedController
    def destroy
      current_user.user_sessions.active.find(params.expect(:id)).revoke!(reason: "revoked_by_user")
      redirect_to account_security_path, notice: "Sessão encerrada."
    end

    def others
      current_id = Authentication::SessionTracker.current_session_id(warden)
      current_user.user_sessions.active.where.not(id: current_id).find_each { |s| s.revoke!(reason: "revoked_by_user") }
      redirect_to account_security_path, notice: "As demais sessões foram encerradas."
    end
  end
end
