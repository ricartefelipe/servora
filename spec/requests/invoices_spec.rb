# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Service invoices" do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:finance) { create(:membership, :finance, organization:) }
  let(:owner) { create(:membership, :owner, organization:) }

  it "configures fiscal data, issues the NFS-e and shows it on the receivable" do
    sign_in_as(owner)
    patch fiscal_settings_path, params: { fiscal_setting: { municipal_service_code: "14.01", iss_rate: "2.5",
                                                            municipal_service_name: "Manutenção de equipamentos" } }
    expect(in_tenant(organization) { FiscalSetting.sole.iss_rate }).to eq(BigDecimal("2.5"))

    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: "640.00")
    receivable = issue_receivable(scenario, work_order, "640.00")
    sign_in_as(finance)
    post receivable_invoices_path(receivable)
    run_dispatcher
    perform_enqueued_jobs(only: Invoices::SubmitJob)

    get receivable_path(receivable)
    expect(response.body).to include("NFS-e nº", "Autorizada", "R$ 640,00")
  end

  it "points to the fiscal settings when they are missing" do
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: "100.00")
    receivable = issue_receivable(scenario, work_order, "100.00")
    sign_in_as(finance)

    get receivable_path(receivable)

    expect(response.body).to include("Configurar dados fiscais")
  end
end
