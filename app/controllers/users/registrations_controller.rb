# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    layout "account"

    rate_limit to: 5, within: 1.hour, only: :create, name: "sign-up",
      with: -> { redirect_to new_user_registration_path, alert: "Muitas tentativas. Tente novamente mais tarde." }

    protected

    def update_resource(resource, params)
      changed_password = params[:password].present?
      updated = super
      revoke_other_sessions(resource) if updated && changed_password
      updated
    end

    def after_inactive_sign_up_path_for(_resource)
      new_user_session_path
    end

    private

    # A password change ends every other session of the account.
    def revoke_other_sessions(user)
      current_id = Authentication::SessionTracker.current_session_id(warden)
      user.user_sessions.active.where.not(id: current_id).find_each { |s| s.revoke!(reason: "password_changed") }
    end
  end
end
