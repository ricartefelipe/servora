# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Receivables" do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:finance) { create(:membership, :finance, organization:) }
  let!(:work_order) { open_work_order(scenario) }

  before { add_authorized_item(scenario, work_order, unit_price: "1200.00", unit_cost: "500") }

  def issue(amount = "1200.00")
    post receivables_path,
      params: { receivable: { work_order_id: work_order.id, amount:, due_on: (Time.zone.today + 5).iso8601 } }
    in_tenant(organization) { Receivable.order(:created_at).last }
  end

  it "bills a work order, registers partial payments once and shows the history" do
    sign_in_as(finance)
    get new_receivable_path(ordem: work_order.id)
    expect(response.body).to include("Saldo a faturar", "R$ 1.200,00")

    receivable = issue
    expect(response).to redirect_to(receivable_path(receivable))
    key = SecureRandom.uuid_v7
    2.times do
      post receivable_payments_path(receivable), params: { payment: { amount: "500", payment_method: "transfer",
                                                                      paid_on: Time.zone.today.iso8601, operation_key: key } }
    end

    get receivable_path(receivable)
    expect(response.body).to include("Parcialmente paga", "R$ 700,00", "Transferência", "Pagamento registrado", "Conta emitida")
    expect(in_tenant(organization) { Payment.count }).to eq(1)
  end

  it "shows rule violations inside the form" do
    sign_in_as(finance)

    params = { receivable: { work_order_id: work_order.id, amount: "5000", due_on: Time.zone.today.iso8601 } }
    post receivables_path, params:, as: :turbo_stream

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("supera o saldo a faturar da ordem (R$ 1.200,00)")
  end

  it "grants discounts, refunds and cancels with reasons" do
    sign_in_as(finance)
    receivable = issue
    post receivable_discounts_path(receivable), params: { discount: { amount: "200", reason: "Cliente recorrente" } }
    post receivable_payments_path(receivable), params: { payment: { amount: "1000", payment_method: "pix",
                                                                    paid_on: Time.zone.today.iso8601,
                                                                    operation_key: SecureRandom.uuid_v7 } }
    payment = in_tenant(organization) { Payment.sole }
    patch refund_receivable_payment_path(receivable, payment),
      params: { refund: { amount: "1000", reason: "Cobrança duplicada" } }
    patch cancel_receivable_path(receivable), params: { cancellation: { reason: "Faturamento refeito" } }

    expect(reload_in_tenant(receivable)).to have_attributes(status: "canceled", discount_amount: 200, refunded_amount: 1000)
    get receivable_path(receivable)
    expect(response.body).to include("Desconto concedido", "Estorno", "Conta cancelada", "Cliente recorrente")
  end

  it "generates a simulated charge and confirms it" do
    sign_in_as(finance)
    receivable = issue("300.00")

    post receivable_charges_path(receivable), params: { charge: { billing_type: "boleto" } }
    run_dispatcher
    perform_enqueued_jobs
    charge = in_tenant(organization) { PaymentCharge.sole }
    post simulate_receivable_charge_path(receivable, charge)

    expect(reload_in_tenant(receivable).status).to eq("paid")
    get receivable_path(receivable)
    expect(response.body).to include("Quitada", "Boleto", "Cobrança paga")
  end

  it "lists receivables with totals and filters" do
    sign_in_as(finance)
    issue("400.00")

    get receivables_path(situacao: "open")

    expect(response.body).to include("Em aberto", "R$ 400,00", work_order.number)
  end

  it "keeps receivables away from operational roles and other organizations" do
    sign_in_as(finance)
    receivable = issue
    sign_in_as(scenario[:coordinator])
    get receivables_path
    expect(response).to have_http_status(:forbidden)

    sign_in_as(create(:membership, :finance))
    get receivable_path(receivable)
    expect(response).to have_http_status(:not_found)
  end

  it "shows billing and margins on the work order to the right roles" do
    sign_in_as(create(:membership, :owner, organization:))
    post work_order_expenses_path(work_order), params: { expense: { category: "parking", description: "Estacionamento",
                                                                    amount: "25", incurred_on: Time.zone.today.iso8601 } }
    follow_redirect!
    expect(response.body).to include("Financeiro", "Faturar", "Margem", "Estacionamento", "R$ 700,00")

    sign_in_as(scenario[:coordinator])
    get work_order_path(work_order)
    expect(response.body).not_to include("Faturar", "Margem")
  end

  it "stores the provider key encrypted and never renders it back" do
    owner = create(:membership, :owner, organization:)
    sign_in_as(owner)

    patch payment_integration_path, params: { payment_integration: { provider: "asaas", default_billing_type: "pix",
                                                                     api_key: "chave-sandbox-123" } }
    get edit_payment_integration_path

    expect(response.body).to include("Chave configurada")
    expect(response.body).not_to include("chave-sandbox-123")
    expect(in_tenant(organization) { PaymentIntegration.sole.api_key }).to eq("chave-sandbox-123")
  end
end
