# frozen_string_literal: true

module Users
  # The e-mail link only renders a page; the confirmation itself is a POST,
  # so link scanners and prefetchers cannot change account state.
  class ConfirmationsController < Devise::ConfirmationsController
    layout "account"

    rate_limit to: 5, within: 15.minutes, only: :create, name: "confirmation",
      with: -> { redirect_to new_user_confirmation_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

    def show
      @confirmation_token = params[:confirmation_token].to_s
      render :show
    end

    def confirm
      self.resource = resource_class.confirm_by_token(params[:confirmation_token].to_s)
      if resource.errors.empty?
        redirect_to new_user_session_path, notice: I18n.t("devise.confirmations.confirmed")
      else
        redirect_to new_user_confirmation_path, alert: "Link de confirmação inválido ou expirado. Solicite um novo."
      end
    end
  end
end
