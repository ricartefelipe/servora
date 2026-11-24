# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Layout responsivo", :js do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }
  let(:customer) { create(:customer, organization:, name: "Rede de Farmácias Bem Estar Comércio de Medicamentos Ltda.") }

  before do
    location = create(:service_location, customer:, name: "Unidade com nome de identificação bastante extenso")
    create(:equipment, location:)
  end

  it "não gera rolagem horizontal nas telas principais em um celular" do
    sign_in_as(owner)
    page.current_window.resize_to(390, 844)

    [dashboard_path, customers_path, customer_path(customer), equipment_index_path, members_path, stock_balances_path,
     stock_movements_path, warehouses_path, receivables_path, contracts_path, sla_settings_path].each do |path|
      visit path
      overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
      expect(overflow).to be <= 0, "#{path} transborda #{overflow}px"
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
