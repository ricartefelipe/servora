# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contracts and preventive plans" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }

  it "creates a draft, activates it and revises terms into a new version" do
    sign_in_as(coordinator)

    post contracts_path, params: { contract: { customer_id: scenario[:customer].id, title: "Climatização da loja",
                                               starts_on: "2026-01-01", monthly_fee: "1500", monthly_visit_limit: "3",
                                               service_type_ids: [scenario[:service_type].id, ""] } }
    contract = in_tenant(organization) { Contract.sole }
    expect(response).to redirect_to(contract_path(contract))
    patch change_status_contract_path(contract), params: { status_change: { to: "active" } }
    patch contract_path(contract), params: { contract: { monthly_fee: "1650", reason: "Reajuste IPCA", service_type_ids: [""] } }

    get contract_path(contract)
    expect(response.body).to include("Vigente", "Versão 2", "Reajuste IPCA", "R$ 1.650,00", "Todos os tipos de serviço")
  end

  it "shows validation errors and requires the reason for revisions in force" do
    contract = create_contract(scenario)
    sign_in_as(coordinator)

    post contracts_path, params: { contract: { customer_id: scenario[:customer].id, title: "", starts_on: "2026-01-01" } }
    expect(response).to have_http_status(:unprocessable_content)

    patch contract_path(contract), params: { contract: { monthly_fee: "10", reason: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Informe o motivo da alteração.")
  end

  it "suspends with a reason and refuses an invalid transition" do
    contract = create_contract(scenario)
    sign_in_as(coordinator)

    patch change_status_contract_path(contract), params: { status_change: { to: "suspended", reason: "Inadimplência" } }
    patch change_status_contract_path(contract), params: { status_change: { to: "draft" } }
    follow_redirect!

    expect(response.body).to include("Suspenso", "Inadimplência", "Não é possível passar de Suspenso")
  end

  it "creates a plan, previews dates and generates occurrences on demand" do
    contract = create_contract(scenario, starts_on: Time.zone.today.beginning_of_month)
    sign_in_as(coordinator)

    post contract_plans_path(contract), params: { maintenance_plan: {
      title: "Preventiva dos splits", service_location_id: scenario[:location].id, service_type_id: scenario[:service_type].id,
      frequency_interval: "1", frequency_unit: "month", schedule_mode: "calendar", anchor_date: Time.zone.today.iso8601,
      lead_days: "0", priority: "normal", equipment_ids: [scenario[:equipment].id, ""]
    } }
    plan = in_tenant(organization) { MaintenancePlan.sole }
    expect(response).to redirect_to(contract_plan_path(contract, plan))
    2.times { post generate_contract_plan_path(contract, plan) }
    follow_redirect!

    expect(response.body).to include("Nenhuma ocorrência pendente.", "nº 1", "Próximas datas", "nº 2")
    order = in_tenant(organization) { MaintenanceOccurrence.sole.work_order }
    get work_order_path(order)
    expect(response.body).to include(contract.number, "Coberto pelo contrato", "Preventiva nº 1")
  end

  it "rejects a plan anchored before the contract start" do
    contract = create_contract(scenario, starts_on: Date.new(2026, 6, 1))
    sign_in_as(coordinator)

    post contract_plans_path(contract), params: { maintenance_plan: {
      title: "Antes do início", service_location_id: scenario[:location].id, frequency_interval: "1", frequency_unit: "month",
      schedule_mode: "calendar", anchor_date: "2026-05-01", lead_days: "0", priority: "normal"
    } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("anterior ao início do contrato")
  end

  it "lets attendants read contracts but not change them" do
    contract = create_contract(scenario)
    sign_in_as(create(:membership, :attendant, organization:))

    get contract_path(contract)
    expect(response.body).not_to include("Alterar condições", "Novo plano")
    patch contract_path(contract), params: { contract: { title: "x" } }
    expect(response).to have_http_status(:forbidden)
  end
end
