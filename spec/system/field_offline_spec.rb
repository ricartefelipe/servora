# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Área do técnico sem conexão", :js do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let!(:work_order) { open_work_order(scenario, title: "Split com ruído") }

  before { in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: scenario[:technician]).call } }

  def network(offline:)
    page.driver.browser.network.emulate_network_conditions(offline:, latency: 0)
  end

  it "guarda o registro no aparelho sem conexão e sincroniza quando a conexão volta" do
    sign_in_as(scenario[:technician])
    visit field_root_path
    click_on "Split com ruído"
    expect(page).to have_text("Pronto para registrar.")

    network(offline: true)
    fill_in "Diagnóstico", with: "Rolamento do ventilador desgastado"
    fill_in "Solução aplicada", with: "Substituição do rolamento"
    click_on "Salvar registro"
    expect(page).to have_text("Sem conexão. As informações estão salvas neste aparelho")
    expect(page).to have_text("1 registro aguardando envio.")
    expect(in_tenant(organization) { work_order.reload.diagnosis }).to be_nil

    network(offline: false)
    page.execute_script("window.dispatchEvent(new Event('online'))")
    expect(page).to have_text("Sincronizado com sucesso.")
    expect(page).to have_no_text("aguardando envio")
    expect(in_tenant(organization) { work_order.reload.diagnosis }).to eq("Rolamento do ventilador desgastado")
  end

  it "recupera o rascunho digitado depois de recarregar a página" do
    sign_in_as(scenario[:technician])
    visit field_work_order_path(work_order)

    fill_in "Diagnóstico", with: "Texto ainda não enviado"
    visit field_work_order_path(work_order)

    expect(page).to have_field("Diagnóstico", with: "Texto ainda não enviado")
    expect(page).to have_text("Rascunho recuperado deste aparelho.")
  end
end
