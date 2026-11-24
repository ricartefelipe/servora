# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform subscription" do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  def subscribe(plan_code, status: "active", trial_ends_on: nil)
    in_tenant(organization) do
      plan = Plan.find_by!(code: plan_code)
      Subscription.create!(organization:, plan:, status:, trial_ends_on:, technician_seats: plan.included_technicians,
        monthly_amount: plan.monthly_price)
    end
  end

  it "hides and blocks modules outside the plan, including the API" do
    subscribe("essencial")
    sign_in_as(owner)

    get dashboard_path
    expect(response.body).not_to include(">Estoque<", ">Financeiro<", ">Contratos<")
    get stock_balances_path
    expect(response).to redirect_to(dashboard_path)
    follow_redirect!
    expect(response.body).to include("não faz parte do plano atual")

    token = in_tenant(organization) do
      Integrations::CreateCredential.new(organization:, actor: owner, name: "ERP", scopes: ["customers:read"]).call.last
    end
    get api_v1_customers_path, headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("module_not_enabled")
  end

  it "keeps data readable but blocks changes after the trial until activation" do
    subscribe("profissional", status: "trialing", trial_ends_on: Time.zone.yesterday)
    sign_in_as(owner)

    get customers_path
    expect(response).to have_http_status(:ok)
    post customers_path, params: { customer: { kind: "company", name: "Novo cliente" } }
    follow_redirect!
    expect(response.body).to include("A avaliação terminou")

    patch subscription_path, params: { subscription: { plan_code: "profissional", seats: "10", addons: [""] }, ativar: "1" }
    expect(in_tenant(organization) { Subscription.sole.status }).to eq("active")
  end

  it "shows plans, seats and the trial to the owner only" do
    subscribe("profissional", status: "trialing", trial_ends_on: Time.zone.today + 5)
    sign_in_as(owner)

    get subscription_path
    expect(response.body).to include("Essencial", "Profissional", "Empresarial", "5 dias", "Vagas de técnico", "R$ 590,00")

    sign_in_as(create(:membership, :admin, organization:))
    get subscription_path
    expect(response).to have_http_status(:forbidden)
  end
end
