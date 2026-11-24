# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Página inicial" do
  it "apresenta a proposta do produto" do
    visit root_path

    expect(page).to have_css("h1", text: "Da solicitação do cliente ao resultado de cada serviço.")
    expect(page).to have_link("Ir para o conteúdo", href: "#conteudo", visible: :all)
  end

  it "oferece entrada e cadastro a quem ainda não entrou" do
    visit root_path

    within("nav[aria-label='Acesso']") do
      expect(page).to have_link("Entrar", href: new_user_session_path)
      expect(page).to have_link("Criar conta", href: new_user_registration_path)
    end
    expect(page).to have_link("Começar agora", href: new_user_registration_path)
    expect(page).to have_link("Já tenho conta", href: new_user_session_path)
    expect(page).to have_no_link("Abrir o painel")
  end

  it "leva do botão Entrar ao formulário de acesso" do
    visit root_path
    within("nav[aria-label='Acesso']") { click_on "Entrar" }

    expect(page).to have_current_path(new_user_session_path)
    expect(page).to have_field("E-mail")
  end

  it "encaminha ao painel quem já entrou" do
    sign_in_as(create(:membership, :owner))

    visit root_path

    within("nav[aria-label='Acesso']") do
      expect(page).to have_link("Abrir o painel", href: dashboard_path)
      expect(page).to have_no_link("Entrar")
    end
    expect(page).to have_link("Continuar no painel", href: dashboard_path)
  end

  it "carrega o JavaScript da aplicação no navegador headless", :js do
    visit root_path

    expect(page).to have_css("h1")
    expect(page.evaluate_script("typeof Turbo")).to eq("object")
  end
end
