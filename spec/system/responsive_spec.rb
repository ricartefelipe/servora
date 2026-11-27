# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Layout responsivo", :js do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }
  let(:customer) { create(:customer, organization:, name: "Rede de Farmácias Bem Estar Comércio de Medicamentos Ltda.") }

  before do
    location = create(:service_location, customer:, name: "Unidade com nome de identificação bastante extenso")
    equipment = create(:equipment, location:)
    create_technician(organization, name: "Diego Alves")
    scenario = { organization:, coordinator: owner, author: owner, customer:, location:, equipment:,
                 service_type: create(:service_type, organization:) }
    open_work_order(scenario, title: "Ar-condicionado da sala de reuniões desarma o disjuntor ao ligar no modo turbo")
    create_quote(scenario)
  end

  it "não gera rolagem horizontal nas telas principais em um celular" do
    sign_in_as(owner)
    page.current_window.resize_to(390, 844)

    [dashboard_path, customers_path, customer_path(customer), equipment_index_path, members_path, stock_balances_path,
     stock_movements_path, warehouses_path, receivables_path, contracts_path, sla_settings_path, field_root_path,
     reports_path, work_orders_path, quotes_path, audit_events_path, agenda_index_path,
     agenda_index_path(visao: "semana")].each do |path|
      visit path
      overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
      expect(overflow).to be <= 0, "#{path} transborda #{overflow}px"
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
