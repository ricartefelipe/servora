# frozen_string_literal: true

module Portal
  class SessionsController < BaseController
    def destroy
      current_portal_session.update!(revoked_at: Time.current)
      cookies.delete(COOKIE)
      redirect_to root_path, notice: "Você saiu do portal."
    end
  end
end
