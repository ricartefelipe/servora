# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contrato e manutenção preventiva", :js do
  let(:scenario) { build_work_order_scenario }

  it "cria contrato, ativa, cadastra plano e gera a ocorrência preventiva" do
    sign_in_as(scenario[:coordinator])
    visit contracts_path
    click_on "Novo contrato"

    select scenario[:customer].display_name, from: "Cliente"
    fill_in "Título", with: "Manutenção mensal da matriz"
    fill_in "Início", with: Time.zone.today.beginning_of_month.iso8601
    fill_in "Mensalidade (R$)", with: "980"
    click_on "Criar contrato"
    expect(page).to have_text("criado como rascunho")

    click_on "Ativar contrato"
    expect(page).to have_text("Vigente")

    click_on "Novo plano"
    fill_in "Título", with: "Preventiva mensal"
    select scenario[:location].name, from: "Local"
    fill_in "Primeira data", with: Time.zone.today.iso8601
    fill_in "Gerar com antecedência (dias)", with: "0"
    click_on "Criar plano"
    expect(page).to have_text("Plano preventivo criado.")

    click_on "Gerar ocorrências devidas"
    expect(page).to have_text("1 ocorrência(s) gerada(s).")
    find("a", text: /OS-\d{4}-\d{5}/).click
    expect(page).to have_text("Preventiva nº 1")
    expect(page).to have_text("Coberto pelo contrato")
  end
end
