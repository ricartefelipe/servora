# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Estoque e materiais da ordem", :js do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let!(:work_order) { open_work_order(scenario) }

  before do
    create(:warehouse, organization:, name: "Almoxarifado central")
    stock_part(organization, name: "Capacitor 35 µF")
  end

  it "registra entrada pelo modal, reserva e consome na ordem de serviço" do
    sign_in_as(scenario[:coordinator])
    visit stock_balances_path
    click_on "Entrada"

    within("dialog") do
      select "Almoxarifado central", from: "Depósito de entrada"
      select "Capacitor 35 µF", from: "Peça"
      fill_in "Custo unitário (R$)", with: "38.40"
      fill_in "Quantidade", with: "4"
      click_on "Registrar entrada"
    end
    expect(page).to have_text("Entrada registrada.")
    expect(page).to have_css("td", text: "Capacitor 35 µF")

    visit work_order_path(work_order)
    click_on "Materiais"
    within("#painel-materiais") do
      select "Almoxarifado central", from: "reserva_deposito"
      select "Capacitor 35 µF", from: "reserva_peca"
      fill_in "reserva_quantidade", with: "3"
      click_on "Reservar"
    end
    expect(page).to have_text("Capacitor 35 µF reservado para a ordem.")

    within("#painel-materiais") do
      select "Capacitor 35 µF · Almoxarifado central (pendente 3)", from: "Reserva"
      fill_in "consumption_quantity", with: "2"
      click_on "Registrar consumo"
    end
    expect(page).to have_text("Consumo registrado na ordem.")
    expect(page).to have_text("Pendente: 1")

    visit stock_balances_path
    expect(page).to have_css("tr", text: /Capacitor 35 µF.*Almoxarifado central.*2.*1.*1/m)
  end
end
