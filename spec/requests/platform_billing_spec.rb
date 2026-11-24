# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform billing" do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  def billed_invoice
    subscription = in_tenant(organization) do
      plan = Plan.find_by!(code: "essencial")
      Subscription.create!(organization:, plan:, status: "active", technician_seats: 3, monthly_amount: plan.monthly_price,
        activated_at: Time.current)
    end
    invoice = in_tenant(organization) { Subscriptions::Bill.new(subscription:).call }
    run_dispatcher
    perform_enqueued_jobs(only: Subscriptions::SubmitInvoiceChargeJob)
    invoice
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "lists the subscription invoices and simulates their payment" do
    invoice = billed_invoice
    sign_in_as(owner)

    get subscription_path
    expect(response.body).to include("Faturas da assinatura", "R$ 249,00", "Simular pagamento")
    post simulate_subscription_invoice_payment_path(invoice)

    expect(reload_in_tenant(invoice).status).to eq("paid")
  end

  it "confirms invoices from authenticated platform notifications, once" do
    invoice = billed_invoice
    payload = { id: "evt_plat_1", event: "PAYMENT_CONFIRMED", payment: { externalReference: invoice.external_reference } }.to_json
    headers = { "Content-Type" => "application/json", "asaas-access-token" => "token-da-plataforma" }

    with_env("PLATFORM_ASAAS_WEBHOOK_TOKEN" => "token-da-plataforma") do
      post platform_asaas_webhook_path, params: payload, headers: headers.merge("asaas-access-token" => "outro")
      expect(response).to have_http_status(:unauthorized)
      2.times { post platform_asaas_webhook_path, params: payload, headers: }
    end
    run_dispatcher
    perform_enqueued_jobs(only: Webhooks::ProcessInboundJob)

    expect(reload_in_tenant(invoice).status).to eq("paid")
    expect(in_tenant(organization) { InboundWebhook.where(provider: "asaas_platform").count }).to eq(1)
  end
end
