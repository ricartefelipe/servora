# frozen_string_literal: true

module Users
  class PasswordsController < Devise::PasswordsController
    layout "account"

    rate_limit to: 5, within: 15.minutes, only: :create, name: "password-reset",
      with: -> { redirect_to new_user_password_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

    protected

    # Resetting the password ends every existing session of the account.
    def after_resetting_password_path_for(resource)
      resource.user_sessions.active.find_each { |s| s.revoke!(reason: "password_reset") }
      super
    end
  end
end
