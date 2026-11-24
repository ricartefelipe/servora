# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding" do
  let(:user) { create(:user) }

  it "sends a user without organizations to the registration form" do
    sign_in user

    get organizations_path

    expect(response).to redirect_to(new_organization_path)
  end

  it "creates the organization and opens its dashboard" do
    sign_in user

    post organizations_path, params: { organization: { name: "Refrigeração Delta", segment: "hvac", time_zone: "America/Manaus",
                                                       travel_buffer_minutes: 25, document: "12.ABC.345/01DE-35" } }
    follow_redirect!

    expect(response.body).to include("Refrigeração Delta")
    expect(response.body).to include("Primeiros passos")
  end

  it "validates the document" do
    sign_in user

    post organizations_path, params: { organization: { name: "X", document: "123" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("não é um CPF ou CNPJ válido")
  end

  it "enrolls MFA with a verified code and shows backup codes once" do
    sign_in user
    get new_account_two_factor_path
    secret = session[:pending_otp_secret]

    post account_two_factor_path, params: { otp_attempt: ROTP::TOTP.new(secret).now }

    expect(response.body).to include("Códigos de recuperação")
    expect(user.reload).to have_attributes(otp_required_for_login: true)
    expect(user.otp_backup_codes.size).to eq(10)
  end
end
