# frozen_string_literal: true

module Integrations
  # Creates an API credential. Returns [credential, token]; only the token's
  # digest and a short prefix (for identification) are stored.
  class CreateCredential
    def initialize(organization:, actor:, name:, scopes:, expires_on: nil)
      @organization = organization
      @actor = actor
      @name = name
      @scopes = Array(scopes).compact_blank
      @expires_on = expires_on.presence
    end

    def call
      token = ApiCredential.generate_token
      credential = ApiCredential.create!(organization_id: @organization.id, name: @name, scopes: @scopes, created_by: @actor,
        token_prefix: token.first(12), token_digest: ApiCredential.digest(token), expires_at:)
      AuditEvent.record!(action: "api_credential.created", auditable: credential, changes: { name: @name, scopes: @scopes })
      [credential, token]
    end

    private

    def expires_at
      return nil unless @expires_on

      date = Date.iso8601(@expires_on)
      raise Servora::RuleViolation, "A validade deve ser uma data futura." unless date.future?

      date.end_of_day
    rescue Date::Error
      raise Servora::RuleViolation, "Data de validade inválida."
    end
  end
end
