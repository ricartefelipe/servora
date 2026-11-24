# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ações em lote na lista de ordens de serviço", :js do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  it "seleciona ordens, move em lote e mostra o resumo" do
    first = open_work_order(scenario, title: "Split não gela")
    second = open_work_order(scenario, title: "Câmara fria com gelo")
    started = open_work_order(scenario, title: "Compressor ruidoso")
    in_tenant(organization) { WorkOrders::Transition.new(work_order: started, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])
    visit work_orders_path

    bar = find("form[aria-label='Ações em lote']", visible: :all)
    expect(bar).not_to be_visible

    check "Selecionar #{first.number}"
    within(bar) { expect(page).to have_text("1 selecionada") }
    header = find_field("Selecionar todas as ordens desta página")
    expect(header.evaluate_script("this.indeterminate")).to be(true)
    expect(page).to have_css("tr[aria-selected='true']", count: 1)

    check "Selecionar todas as ordens desta página"
    within(bar) { expect(page).to have_text("3 selecionadas") }
    expect(header.evaluate_script("this.indeterminate")).to be(false)

    within(bar) do
      select "Agendada", from: "Mover para"
      click_on "Aplicar"
    end

    expect(page).to have_text("3 ordens atualizadas para Agendada.")
    expect(in_tenant(organization) { [first, second, started].map { |work_order| work_order.reload.status } }.uniq)
      .to eq(["scheduled"])
    expect(page).to have_css("form[aria-label='Ações em lote']", visible: :hidden)
  end

  it "exige o motivo para as esperas e limpa a seleção" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])
    visit work_orders_path

    check "Selecionar #{work_order.number}"
    within("form[aria-label='Ações em lote']") do
      select "Aguardando peças", from: "Mover para"
      expect(find_field("Motivo")[:required]).to be(true)
      click_on "Limpar seleção"
    end

    expect(page).to have_unchecked_field("Selecionar #{work_order.number}")
    expect(page).to have_css("form[aria-label='Ações em lote']", visible: :hidden)
  end

  it "lembra a densidade compacta da tabela" do
    open_work_order(scenario)
    sign_in_as(scenario[:coordinator])
    visit work_orders_path

    choose "Compacta", allow_label_click: true
    expect(page).to have_css("body[data-density='compact']")

    visit work_orders_path
    expect(page).to have_css("body[data-density='compact']")
    expect(page).to have_checked_field("Compacta", visible: :all)
  end
end
