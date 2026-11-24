# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Navegação e permissões na interface" do
  let(:organization) { create(:organization, name: "Clima Serra") }

  it "mostra somente os itens permitidos ao perfil" do
    sign_in_as(create(:membership, :technician, organization:))

    visit dashboard_path

    within("aside#navegacao") do
      expect(page).to have_link("Painel")
      expect(page).to have_no_link("Equipe")
      expect(page).to have_no_link("Auditoria")
    end
  end

  it "exibe a página de acesso negado ao tentar uma rota sem permissão" do
    sign_in_as(create(:membership, :technician, organization:))

    visit audit_events_path

    expect(page).to have_text("Acesso negado")
    expect(page.status_code).to eq(403)
  end

  it "abre e fecha o menu em telas pequenas pelo teclado", :js do
    sign_in_as(create(:membership, :owner, organization:))
    page.current_window.resize_to(390, 844)

    visit dashboard_path
    expect(page).to have_button("Abrir navegação")
    expect(page).to have_no_css("aside#navegacao a", text: "Equipe", visible: :visible)

    click_on "Abrir navegação"
    expect(page).to have_css("aside#navegacao a", text: "Equipe", visible: :visible)
    expect(page).to have_button("Abrir navegação", visible: :all) { |b| b["aria-expanded"] == "true" }

    page.send_keys(:escape)
    expect(page).to have_no_css("aside#navegacao a", text: "Equipe", visible: :visible)
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
