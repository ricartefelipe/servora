# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::Bill do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization, document: "11222333000181") }

  def subscribe(activated_on:, implementation: "pending")
    in_tenant(organization) do
      plan = Plan.find_by!(code: "profissional")
      Subscription.create!(organization:, plan:, status: "active", technician_seats: 10, monthly_amount: BigDecimal("590.00"),
        implementation_fee: BigDecimal("1500.00"), implementation_status: implementation,
        activated_at: Time.zone.local(activated_on.year, activated_on.month, activated_on.day, 10))
    end
  end

  def bill(subscription, today) = in_tenant(organization) { described_class.new(subscription: subscription.reload, today:).call }
  def invoices = in_tenant(organization) { SubscriptionInvoice.order(:period_start).to_a }

  it "bills prepaid monthly periods anchored on the activation day, once per period" do
    subscription = subscribe(activated_on: Date.new(2026, 1, 31))

    2.times { bill(subscription, Date.new(2026, 1, 31)) }
    bill(subscription, Date.new(2026, 2, 27))
    bill(subscription, Date.new(2026, 2, 28))

    expect(invoices.map { |invoice| [invoice.period_start.iso8601, invoice.period_end.iso8601, invoice.amount.to_s("F")] })
      .to eq([%w[2026-01-31 2026-02-28 2090.0], %w[2026-02-28 2026-03-31 590.0]])
    expect(invoices.first.lines.pluck("description")).to eq(["Plano Profissional", "Implantação e treinamento"])
    expect(invoices.first.due_on).to eq(Date.new(2026, 2, 5))
  end

  it "charges through the platform account after commit and settles the implementation fee on payment" do
    subscription = subscribe(activated_on: Date.new(2026, 11, 2))
    invoice = bill(subscription, Date.new(2026, 11, 2))

    run_dispatcher
    perform_enqueued_jobs(only: Subscriptions::SubmitInvoiceChargeJob)
    expect(reload_in_tenant(invoice)).to have_attributes(charge_status: "submitted",
      external_id: "sim_#{invoice.external_reference}")

    2.times { Subscriptions::ConfirmInvoice.new(organization_id: organization.id, invoice_id: invoice.id).call }

    expect(reload_in_tenant(invoice).status).to eq("paid")
    expect(reload_in_tenant(subscription).implementation_status).to eq("paid")
  end

  it "makes the subscription past due after the grace period and reactivates it on payment" do
    subscription = subscribe(activated_on: Date.new(2026, 10, 1), implementation: "paid")
    invoice = bill(subscription, Date.new(2026, 10, 1))

    bill(subscription, Date.new(2026, 10, 13))
    expect(reload_in_tenant(subscription).status).to eq("active")
    bill(subscription, Date.new(2026, 10, 14))
    expect(reload_in_tenant(subscription)).to have_attributes(status: "past_due", read_only?: true)

    Subscriptions::ConfirmInvoice.new(organization_id: organization.id, invoice_id: invoice.id).call
    expect(reload_in_tenant(subscription).status).to eq("active")
  end

  it "does not bill trials" do
    trial = in_tenant(organization) do
      plan = Plan.find_by!(code: "empresarial")
      Subscription.create!(organization:, plan:, status: "trialing", trial_ends_on: Date.new(2026, 12, 1), technician_seats: 30,
        monthly_amount: plan.monthly_price)
    end

    expect(bill(trial, Date.new(2026, 11, 20))).to be_nil
    expect(invoices).to be_empty
  end

  it "runs daily for every organization" do
    subscribe(activated_on: Date.current)

    Subscriptions::BillingJob.perform_now

    expect(invoices.size).to eq(1)
  end
end
