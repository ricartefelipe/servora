# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agendamento e despacho", :js do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  it "agenda uma equipe, recusa o horário conflitante e mostra a linha do tempo" do
    diego = create_technician(organization, name: "Diego Alves")
    eduarda = create_technician(organization, name: "Eduarda Lima")
    in_tenant(organization) do
      team = Team.create!(organization:, name: "Equipe Norte")
      [diego, eduarda].each { |member| TeamMember.create!(organization:, team:, membership: member) }
    end
    first_order = open_work_order(scenario, title: "Instalação de cassete")
    second_order = open_work_order(scenario, title: "Manutenção corretiva")
    sign_in_as(scenario[:coordinator])

    visit new_work_order_visit_path(first_order)
    fill_in "Data", with: Date.new(2026, 12, 1)
    fill_in "Início", with: "09:00"
    select "Equipe Norte", from: "Ou uma equipe inteira"
    # The form proposes the next business day, so the first suggestions already list working technicians.
    within("#visit-suggestions") { expect(page).to have_text("Diego Alves") }
    click_on "Agendar"
    expect(page).to have_text("Visita agendada para 01/12/2026 09:00")
    expect(page).to have_link(first_order.number, count: 2)

    visit new_work_order_visit_path(second_order)
    fill_in "Data", with: Date.new(2026, 12, 1)
    fill_in "Início", with: "10:00"
    check "Eduarda Lima"
    click_on "Agendar"

    expect(page).to have_css("[role=alert]", text: "Conflito de agenda")
    expect(page).to have_text("Eduarda Lima tem visita da #{first_order.number}")
  end
end
