# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acesso à demonstração", :demo_mode, :js do
  let(:organization) { create(:organization, name: "Refrigeração Aurora", mfa_required_for_privileged: true) }

  let(:user) { create(:user, name: "Ana Ribeiro", password: Servora::Demo.password) }

  # The test database may hold the seeded accounts, so the profile points to a
  # person created here instead of the seeded e-mail.
  before do
    create(:membership, :owner, organization:, user:)
    stub_const("Servora::Demo::ACCOUNTS",
      [Servora::Demo::Account.new(email: user.email, role: "owner", profile: "Proprietária", note: nil)])
  end

  it "preenche o acesso ao escolher um perfil e entra sem exigir verificação em duas etapas" do
    visit "/"

    within("section[aria-labelledby='demo-access-title']") do
      expect(page).to have_css("code", text: Servora::Demo.password)
      click_button user.email
    end

    expect(page).to have_field("E-mail", with: user.email)
    expect(page).to have_field("Senha", with: Servora::Demo.password)
    expect(page).to have_css("[aria-live=polite]", text: "Proprietária: e-mail e senha preenchidos.", visible: :all)
    expect(page.evaluate_script("document.activeElement.type")).to eq("submit")

    click_on "Entrar"

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_text("Refrigeração Aurora")
    expect(page).to have_no_text("Seu perfil exige verificação em duas etapas")
  end
end
