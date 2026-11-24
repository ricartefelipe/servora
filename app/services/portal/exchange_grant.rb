# frozen_string_literal: true

module Portal
  # Exchanges a valid, unused grant for a restricted portal session.
  class ExchangeGrant
    Result = Data.define(:session_token, :session, :grant)

    class InvalidGrant < Servora::RuleViolation; end

    def self.organization_for(token)
      return nil if token.blank?

      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT servora_resolve_portal_grant(?)", PortalAccessGrant.digest(token)])
      )
    end

    def initialize(token:, ip:, user_agent:)
      @token = token.to_s
      @ip = ip
      @user_agent = user_agent.to_s.first(255)
    end

    def call
      organization_id = self.class.organization_for(@token)
      raise InvalidGrant, "Link de acesso inválido." unless organization_id

      Servora::Tenancy.with_organization(organization_id) do
        grant = PortalAccessGrant.lock.includes(contact: :customer).find_by!(token_digest: PortalAccessGrant.digest(@token))
        ensure_usable!(grant)
        grant.update!(used_at: Time.current)
        session_token = SecureRandom.urlsafe_base64(32)
        session = PortalSession.create!(
          organization_id:, contact: grant.contact, grant:, ip_address: @ip, user_agent: @user_agent,
          token_digest: PortalAccessGrant.digest(session_token), expires_at: PortalSession::DURATION.from_now,
          last_seen_at: Time.current
        )
        Result.new(session_token:, session:, grant:)
      end
    end

    private

    def ensure_usable!(grant)
      raise InvalidGrant, "Este link já foi utilizado, expirou ou foi revogado. Solicite um novo." unless grant.usable?

      contact = grant.contact
      return if contact.portal_enabled? && !contact.archived? && !contact.customer.archived?

      raise InvalidGrant, "O acesso ao portal não está disponível para este contato."
    end
  end
end
