# frozen_string_literal: true

module Users
  class UnlocksController < Devise::UnlocksController
    layout "account"

    rate_limit to: 5, within: 15.minutes, only: :create, name: "unlock",
      with: -> { redirect_to new_user_unlock_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

    def show
      @unlock_token = params[:unlock_token].to_s
      render :show
    end

    def confirm
      self.resource = resource_class.unlock_access_by_token(params[:unlock_token].to_s)
      if resource.errors.empty?
        redirect_to new_user_session_path, notice: I18n.t("devise.unlocks.unlocked")
      else
        redirect_to new_user_unlock_path, alert: "Link de desbloqueio inválido. Solicite um novo."
      end
    end
  end
end
