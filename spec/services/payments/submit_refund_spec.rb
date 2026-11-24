# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::SubmitRefund do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:finance) { create(:membership, :finance, organization:) }

  def paid_by_charge(amount)
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: amount)
    receivable = issue_receivable(scenario, work_order, amount)
    charge = as_member(finance) { Payments::RequestCharge.new(receivable:, actor: finance).call }
    settle(charge)
  end

  def settle(charge)
    Payments::SubmitCharge.new(organization_id: organization.id, charge_id: charge.id).call
    Payments::ConfirmCharge.new(organization_id: organization.id, charge_id: charge.id).call
    in_tenant(organization) { Payment.find_by!(payment_charge_id: charge.id) }
  end

  def refund(payment, amount)
    as_member(finance) { Receivables::RefundPayment.new(payment: payment.reload, amount:, reason: "Serviço não executado", actor: finance).call }
    in_tenant(organization) { PaymentRefund.order(:created_at).last }
  end

  def submit(refund) = described_class.new(organization_id: organization.id, refund_id: refund.id).call

  it "sends refunds of provider charges after commit and records the acceptance" do
    payment = paid_by_charge("400.00")
    pending = refund(payment, "150.00")
    expect(pending.status).to eq("pending")

    run_dispatcher
    expect(Payments::SubmitRefundJob).to have_been_enqueued.with(organization.id, pending.id)
    perform_enqueued_jobs(only: Payments::SubmitRefundJob)

    expect(reload_in_tenant(pending)).to have_attributes(status: "accepted", attempts: 1, external_id: "sim_refund_#{pending.id}")
  end

  it "flags refunds of manual payments for the finance team" do
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: "90.00")
    payment = pay(issue_receivable(scenario, work_order, "90.00"), "90.00")

    expect(refund(payment, "90.00")).to have_attributes(status: "manual")
    expect(in_tenant(organization) { OutboxEvent.where(event_type: "payment_refund.requested").count }).to eq(0)
  end

  it "never resends a refund whose outcome is unknown until a person decides" do
    payment = paid_by_charge("500.00")
    uncertain = refund(payment, "120.13")

    submit(uncertain)
    expect(reload_in_tenant(uncertain)).to have_attributes(status: "unknown", attempts: 1)
    submit(uncertain)
    expect(reload_in_tenant(uncertain).attempts).to eq(1)

    as_member(finance) { Payments::ResolveRefund.new(refund: uncertain.reload, action: "confirm", actor: finance).call }
    expect(reload_in_tenant(uncertain)).to have_attributes(status: "accepted", resolved_by_membership_id: finance.id)
  end

  it "records refusals and allows an explicit resend" do
    payment = paid_by_charge("300.00")
    refused = refund(payment, "40.66")

    submit(refused)
    expect(reload_in_tenant(refused)).to have_attributes(status: "failed", last_error: /recusado/)

    as_member(finance) { Payments::ResolveRefund.new(refund: refused.reload, action: "retry", actor: finance).call }
    expect(reload_in_tenant(refused).status).to eq("pending")
    expect do
      as_member(finance) { Payments::ResolveRefund.new(refund: refused.reload, action: "confirm", actor: finance).call }
    end.to raise_error(Servora::RuleViolation, /não precisa de verificação/)
  end
end
