# frozen_string_literal: true

module Portal
  class SessionsController < BaseController
    skip_around_action :within_portal_session, only: :show

    def show
      @title = "Você saiu do portal"
      @message = "Sua sessão foi encerrada. Para voltar, use o link enviado pela empresa que atende você."
      render "portal/home/signed_out"
    end

    def destroy
      current_portal_session.update!(revoked_at: Time.current)
      cookies.delete(COOKIE)
      redirect_to portal_signed_out_path
    end
  end
end
