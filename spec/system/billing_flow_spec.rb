# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Faturamento e cobrança", :js do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:finance) { create(:membership, :finance, organization:) }
  let!(:work_order) { open_work_order(scenario) }

  before { add_authorized_item(scenario, work_order, unit_price: "850.00", unit_cost: "300") }

  it "fatura a ordem, gera cobrança simulada e confirma o pagamento" do
    sign_in_as(finance)
    visit work_order_path(work_order)

    within("#financeiro") { click_on "Faturar" }
    within("dialog") do
      expect(page).to have_field("Valor (R$)", with: "850.0")
      click_on "Emitir conta"
    end
    expect(page).to have_text(/Conta FAT-\d{4}-00001 emitida/)
    expect(page).to have_text("Em aberto")

    select "Pix", from: "Forma da cobrança"
    click_on "Gerar cobrança"
    expect(page).to have_text("Cobrança solicitada")
    run_dispatcher # jobs run inline in system specs
    visit current_path

    click_on "Simular pagamento"
    expect(page).to have_text("Pagamento simulado confirmado.")
    expect(page).to have_text("Quitada")
    expect(page).to have_text("Cobrança paga")
  end
end
