# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Porta de entrada" do
  let(:membership) { create(:membership, :owner) }

  it "abre o formulário de acesso na raiz da aplicação" do
    visit "/"

    expect(page).to have_css("h1", text: "Entrar no Servora")
    expect(page).to have_field("E-mail")
    expect(page).to have_field("Senha")
    expect(page).to have_link("Ir para o conteúdo", href: "#conteudo", visible: :all)
    expect(page).to have_link("Criar conta", href: new_user_registration_path)
  end

  it "mantém o endereço antigo de acesso redirecionando para a raiz" do
    visit "/conta/entrar"

    expect(page).to have_current_path("/")
    expect(page).to have_field("E-mail")
  end

  it "entra pela raiz e leva às organizações da pessoa" do
    visit "/"
    fill_in "E-mail", with: membership.user.email
    fill_in "Senha", with: membership.user.password
    click_on "Entrar"

    expect(page).to have_no_field("Senha")
    expect(page).to have_no_current_path("/")
  end

  it "encaminha quem já entrou sem exibir o formulário de acesso" do
    sign_in_as(membership)

    visit "/"

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_no_field("Senha")
    expect(page).to have_no_text("Você já está autenticado")
  end

  it "carrega o JavaScript da aplicação no navegador headless", :js do
    visit "/"

    expect(page).to have_css("h1")
    expect(page.evaluate_script("typeof Turbo")).to eq("object")
  end
end
