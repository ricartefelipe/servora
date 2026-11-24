# frozen_string_literal: true

module Users
  # Sign in in two steps when the account has MFA enabled:
  #   1. e-mail + password (failed attempts count towards Devise lockable);
  #   2. TOTP or backup code within MFA_WINDOW, also counted as attempts.
  # Error messages never reveal whether the e-mail exists.
  class SessionsController < Devise::SessionsController
    MFA_WINDOW = 5.minutes
    PENDING_KEY = :mfa_pending

    layout "account"

    rate_limit to: 10, within: 3.minutes, only: %i[create verify_two_factor], name: "sign-in",
      with: -> { redirect_to new_user_session_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

    prepend_before_action :start_two_factor, only: :create

    def create = super

    def two_factor
      return redirect_to(new_user_session_path, alert: "Entre novamente para continuar.") unless pending_user

      render :two_factor
    end

    def verify_two_factor
      user = pending_user
      return redirect_to(new_user_session_path, alert: "Entre novamente para continuar.") unless user

      if user.valid_for_authentication? { valid_second_factor?(user, params[:otp_attempt].to_s) }
        session.delete(PENDING_KEY)
        sign_in(:user, user)
        redirect_to after_sign_in_path_for(user), notice: I18n.t("devise.sessions.signed_in")
      else
        flash.now[:alert] = user.access_locked? ? I18n.t("devise.failure.locked") : "Código inválido. Tente novamente."
        render :two_factor, status: :unprocessable_content
      end
    end

    private

    # Accounts with MFA are diverted to the second step after the password is
    # verified; accounts without MFA continue through the standard Devise flow.
    def start_two_factor
      credentials = params.fetch(:user, {}).permit(:email, :password)
      user = User.find_for_authentication(email: credentials[:email].to_s.strip.downcase)
      return unless user&.otp_required_for_login?

      return reject_credentials(user) unless user.valid_for_authentication? { user.valid_password?(credentials[:password].to_s) }
      return reject_inactive(user) unless user.active_for_authentication?

      session[PENDING_KEY] = { "user_id" => user.id, "at" => Time.current.to_i }
      redirect_to user_two_factor_challenge_path
    end

    def pending_user
      data = session[PENDING_KEY]
      return nil unless data.is_a?(Hash) && Time.zone.at(data["at"].to_i) > MFA_WINDOW.ago

      User.find_by(id: data["user_id"])
    end

    def valid_second_factor?(user, code)
      return false if code.blank?

      user.validate_and_consume_otp!(code) || consume_backup_code(user, code)
    end

    def consume_backup_code(user, code)
      return false unless user.invalidate_otp_backup_code!(code.delete(" "))

      user.save!(validate: false)
    end

    def reject_credentials(user)
      message = user.access_locked? ? I18n.t("devise.failure.locked") : I18n.t("devise.failure.invalid")
      redirect_to new_user_session_path, alert: message
    end

    def reject_inactive(user)
      redirect_to new_user_session_path, alert: I18n.t("devise.failure.#{user.inactive_message}")
    end
  end
end
