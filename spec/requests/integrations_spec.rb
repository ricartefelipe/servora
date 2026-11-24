# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integrations" do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  it "creates a scoped credential, shows the token once and revokes it" do
    sign_in_as(owner)

    post create_credential_integrations_path, params: { api_credential: { name: "ERP", scopes: ["customers:read", ""] } }

    token = response.body[/svk_[\w-]+/]
    expect(response).to have_http_status(:created)
    expect(response.body).to include("não será exibido novamente")
    credential = in_tenant(organization) { ApiCredential.sole }
    expect(credential.token_digest).to eq(ApiCredential.digest(token))
    expect(credential.attributes.values.join).not_to include(token)

    get integrations_path
    expect(response.body).not_to include(token)
    patch revoke_credential_integrations_path(id: credential.id)
    expect(in_tenant(organization) { credential.reload.revoked_at }).to be_present
  end

  it "explains invalid webhook endpoints" do
    sign_in_as(owner)

    post create_endpoint_integrations_path, params: { webhook_endpoint: { url: "http://erp.exemplo.com.br", events: [""] } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("use uma URL https", "selecione ao menos um evento")
  end

  it "authenticates provider notifications with the rotated token" do
    sign_in_as(owner)
    post rotate_payment_token_integrations_path
    token = response.body[/value="([\w-]{40,})"/, 1]

    post asaas_webhook_path, params: { id: "evt_9", event: "PAYMENT_CREATED" }.to_json,
      headers: { "Content-Type" => "application/json", "asaas-access-token" => "errado" }
    expect(response).to have_http_status(:unauthorized)

    post asaas_webhook_path, params: { id: "evt_9", event: "PAYMENT_CREATED" }.to_json,
      headers: { "Content-Type" => "application/json", "asaas-access-token" => token }
    expect(response).to have_http_status(:ok)
    expect(in_tenant(organization) { InboundWebhook.count }).to eq(1)
  end

  it "is restricted to who manages integrations" do
    sign_in_as(create(:membership, :coordinator, organization:))

    get integrations_path

    expect(response).to have_http_status(:forbidden)
  end
end
