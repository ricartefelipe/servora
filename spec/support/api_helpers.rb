# frozen_string_literal: true

module ApiHelpers
  def api_token(membership, scopes: ApiCredential::SCOPES.keys, expires_on: nil)
    in_tenant(membership.organization) do
      Integrations::CreateCredential.new(organization: membership.organization, actor: membership, name: "ERP",
        scopes:, expires_on:).call.last
    end
  end

  def api_headers(token, **extra) = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }.merge(extra)
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
