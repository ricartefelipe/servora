# frozen_string_literal: true

module Account
  # TOTP enrollment. The secret is kept in the session until the first code is
  # verified, then stored encrypted (Active Record Encryption). Backup codes are
  # shown once and stored hashed.
  class TwoFactorsController < AuthenticatedController
    SECRET_KEY = :pending_otp_secret

    rate_limit to: 10, within: 10.minutes, only: %i[create destroy], name: "mfa",
      with: -> { redirect_to account_security_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

    def new
      if current_user.mfa_enabled?
        return redirect_to(account_security_path,
          notice: "A verificação em duas etapas já está ativa.")
      end

      session[SECRET_KEY] ||= User.generate_otp_secret
      @provisioning = Authentication::TotpProvisioning.new(user: current_user, secret: session[SECRET_KEY])
    end

    def create
      secret = session[SECRET_KEY]
      return redirect_to(new_account_two_factor_path) if secret.blank?

      if current_user.validate_and_consume_otp!(params[:otp_attempt].to_s, otp_secret: secret)
        @backup_codes = enable!(secret)
        render :backup_codes
      else
        @provisioning = Authentication::TotpProvisioning.new(user: current_user, secret:)
        flash.now[:alert] = "Código inválido. Confira o horário do aparelho e tente novamente."
        render :new, status: :unprocessable_content
      end
    end

    def destroy
      unless current_user.valid_password?(params[:current_password].to_s)
        return redirect_to(account_security_path, alert: "Senha atual incorreta.")
      end

      current_user.update!(otp_required_for_login: false, otp_secret: nil, otp_backup_codes: nil)
      redirect_to account_security_path, notice: "Verificação em duas etapas desativada."
    end

    private

    def enable!(secret)
      session.delete(SECRET_KEY)
      codes = nil
      current_user.with_lock do
        current_user.otp_secret = secret
        current_user.otp_required_for_login = true
        codes = current_user.generate_otp_backup_codes!
        current_user.save!
      end
      codes
    end
  end
end
