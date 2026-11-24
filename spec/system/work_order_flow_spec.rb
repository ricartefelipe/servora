# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Execução e conclusão de uma ordem de serviço", :js do
  let(:scenario) { build_work_order_scenario }

  it "registra checklist e diagnóstico, conclui e mostra o relatório" do
    work_order = open_work_order(scenario)
    in_tenant(scenario[:organization]) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])
    visit work_order_path(work_order)

    within("li", text: "Medir pressão de sucção") do
      fill_in "Medir pressão de sucção", with: "68"
      click_on "Salvar"
    end
    expect(page).to have_text("Checklist atualizado")
    within("li", text: "Limpar filtros") do
      select "Sim", from: "Limpar filtros"
      click_on "Salvar"
    end
    within("li", text: "Limpar filtros") { expect(page).to have_text("sim ·") }
    fill_in "Diagnóstico", with: "Filtro obstruído"
    fill_in "Solução aplicada", with: "Limpeza do filtro e teste de funcionamento"
    click_on "Salvar registro técnico"
    expect(page).to have_text("Diagnóstico e solução salvos")

    accept_confirm { click_on "Concluir" }

    expect(page).to have_text("Ordem de serviço concluída")
    expect(page).to have_css(".sv-badge", text: "Concluída")
    click_on "Relatórios"
    expect(page).to have_text("Relatório versão 1")
    expect(page).to have_text("Filtro obstruído")
  end
end
