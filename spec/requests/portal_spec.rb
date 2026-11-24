# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer portal" do
  let(:scenario) { build_quote_scenario }
  let(:organization) { scenario[:organization] }

  it "does not consume the link on GET" do
    token = portal_token_for(scenario[:approver])

    get portal_access_path(token)
    get portal_access_path(token)
    expect(response.body).to include("Continuar")

    post portal_access_path(token)
    expect(response).to redirect_to(portal_root_path)
    post portal_access_path(token)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "approves the current version from the portal" do
    quote = create_quote(scenario)
    version = send_quote(scenario, quote)
    enter_portal(scenario[:approver])

    get portal_quote_path(quote)
    expect(response.body).to include("Manutenção preventiva", "Aprovar proposta")
    expect(response.body).not_to include("unit_cost", "Custo")

    post decide_portal_quote_path(quote), params: { decision: { outcome: "approved", version_id: version.id,
                                                                content_digest: version.content_digest } }

    expect(in_tenant(organization) { version.reload }).to have_attributes(status: "approved", decision_channel: "portal")
  end

  it "restricts the contact to quotes of their own customer" do
    other_customer_quote = create_quote(build_quote_scenario(organization:))
    enter_portal(scenario[:approver])

    get portal_quote_path(other_customer_quote)

    expect(response).to have_http_status(:not_found)
  end

  it "never shows draft versions" do
    quote = create_quote(scenario)
    enter_portal(scenario[:approver])

    get portal_quote_path(quote)

    expect(response).to have_http_status(:not_found)
  end

  it "ends access when the contact loses portal permission or logs out" do
    enter_portal(scenario[:approver])
    get portal_root_path
    expect(response).to have_http_status(:ok)

    in_tenant(organization) { scenario[:approver].update!(portal_enabled: false) }
    get portal_root_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "signs out to a portal page instead of the staff sign-in form" do
    enter_portal(scenario[:approver])

    delete portal_sign_out_path
    expect(response).to redirect_to(portal_signed_out_path)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Você saiu do portal", "link enviado pela empresa")
    expect(response.body).not_to include("Entrar no Servora")

    get portal_root_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "requires a portal session" do
    get portal_quotes_path

    expect(response).to have_http_status(:unauthorized)
  end

  it "does not accept staff sessions as portal sessions" do
    sign_in_as(scenario[:author])

    get portal_root_path

    expect(response).to have_http_status(:unauthorized)
  end
end
