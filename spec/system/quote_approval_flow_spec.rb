# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orçamento do rascunho à aprovação no portal", :js do
  let(:organization) { create(:organization, name: "Clima Norte") }
  let(:attendant) { create(:membership, :attendant, organization:) }
  let(:customer) { create(:customer, organization:, name: "Hotel Atlântico") }

  before do
    create(:service_location, customer:, name: "Recepção")
    create(:customer_contact, customer:, name: "Sofia Lins", email: "sofia@hotel.test", can_approve: true, portal_enabled: true)
    create(:catalog_item, organization:, name: "Limpeza de evaporadora", unit_price: BigDecimal("180.00"))
  end

  it "monta, envia e aprova a proposta" do
    sign_in_as(attendant)
    visit new_quote_path
    select "Recepção — São Paulo/SP", from: "Cliente e local"
    fill_in "Título", with: "Limpeza dos splits da recepção"
    click_on "Criar orçamento"
    expect(page).to have_text("Orçamento ORC-")

    select "Limpeza de evaporadora — R$ 180,00/un", from: "Item do catálogo"
    fill_in "Qtd.", with: "3", match: :first
    click_on "Incluir", match: :first
    expect(page).to have_text("R$ 540,00")

    accept_confirm { click_on "Enviar ao cliente" }
    expect(page).to have_text("Versão 1 enviada ao cliente")
    expect(page).to have_text("Conteúdo congelado")

    run_dispatcher
    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{http://\S+/portal/acesso/[\w-]+}]
    expect(ActionMailer::Base.deliveries.last.to).to eq(["sofia@hotel.test"])

    visit URI.parse(link).request_uri
    click_on "Continuar"
    expect(page).to have_text("Limpeza dos splits da recepção")
    accept_confirm { click_on "Aprovar proposta de R$ 540,00" }

    expect(page).to have_text("Proposta aprovada")
    expect(page).to have_text("Aprovada por Sofia Lins")
  end
end
