# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Clientes, locais e equipamentos", :js do
  let(:organization) { create(:organization) }
  let(:attendant) { create(:membership, :attendant, organization:) }

  it "cadastra cliente, adiciona local pelo modal e registra um equipamento" do
    sign_in_as(attendant)
    visit customers_path
    click_on "Novo cliente", match: :first

    choose "Pessoa jurídica"
    fill_in "Nome ou razão social", with: "Supermercado Horizonte Ltda."
    fill_in "CPF ou CNPJ", with: "11.222.333/0001-81"
    fill_in "Identificação", with: "Loja 1"
    fill_in "Logradouro", with: "Av. Brasil"
    fill_in "Cidade", with: "Campinas"
    select "São Paulo", from: "UF"
    fill_in "Nome", with: "Paula Reis"
    click_on "Cadastrar cliente"
    expect(page).to have_text("Cliente cadastrado")

    click_on "Novo local"
    within("dialog") do
      fill_in "Identificação", with: "Centro de distribuição"
      fill_in "Logradouro", with: "Rodovia Anhanguera, km 100"
      fill_in "Cidade", with: "Sumaré"
      click_on "Adicionar local"
      expect(page).to have_text("Revise os campos destacados")
      expect(page).to have_field("UF", with: "") { |field| field["aria-invalid"] == "true" }
      select "São Paulo", from: "UF"
      click_on "Adicionar local"
    end
    expect(page).to have_text("Local de atendimento adicionado")
    expect(page).to have_text("Centro de distribuição")

    click_on "Equipamento"
    select "Centro de distribuição", from: "Local de instalação"
    fill_in "Tipo", with: "Câmara fria"
    fill_in "Número de série", with: "cf-778"
    click_on "Cadastrar equipamento"

    expect(page).to have_text("Equipamento cadastrado")
    expect(page).to have_text("Supermercado Horizonte Ltda. · Centro de distribuição")
    expect(page).to have_text("CF-778")
  end

  it "fecha o modal pelo teclado e devolve o foco" do
    customer = create(:customer, organization:, name: "Hotel Mirante")
    create(:service_location, customer:)
    sign_in_as(attendant)
    visit customer_path(customer)

    click_on "Novo local"
    expect(page).to have_css("dialog[open]")
    page.send_keys(:escape)

    expect(page).to have_no_css("dialog[open]")
    expect(page.evaluate_script("document.activeElement.textContent")).to include("Novo local")
  end
end
