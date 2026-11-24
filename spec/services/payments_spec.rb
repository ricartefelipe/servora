# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }
  let!(:work_order) { open_work_order(scenario) }

  def receivable_of(amount)
    add_authorized_item(scenario, work_order, unit_price: amount)
    issue_receivable(scenario, work_order, amount)
  end

  def request_charge(receivable, billing_type: "pix")
    as_member(coordinator) { Payments::RequestCharge.new(receivable:, actor: coordinator, billing_type:).call }
  end

  def submit(charge) = Payments::SubmitCharge.new(organization_id: organization.id, charge_id: charge.id).call
  def confirm(charge) = Payments::ConfirmCharge.new(organization_id: organization.id, charge_id: charge.id).call

  def events(receivable)
    in_tenant(organization) { FinancialEvent.where(receivable_id: receivable.id).order(:occurred_at, :id).pluck(:kind) }
  end

  it "submits the charge after commit through the outbox and confirms the payment once" do
    receivable = receivable_of("480.00")
    charge = request_charge(receivable)

    run_dispatcher
    expect(Payments::SubmitChargeJob).to have_been_enqueued.with(organization.id, charge.id)
    perform_enqueued_jobs

    expect(reload_in_tenant(charge)).to have_attributes(status: "submitted", external_id: "sim_#{charge.external_reference}")
    2.times { confirm(charge) }
    expect(reload_in_tenant(receivable)).to have_attributes(status: "paid", paid_amount: 480)
    expect(in_tenant(organization) { Payment.where(payment_charge_id: charge.id).count }).to eq(1)
    expect(events(receivable)).to eq(%w[issued charge_requested charge_submitted payment charge_confirmed])
  end

  it "keeps a single charge per receivable in flight" do
    receivable = receivable_of("100.00")
    request_charge(receivable)

    expect { request_charge(receivable) }.to raise_error(Receivables::Errors::Invalid, /cobrança em andamento/)
  end

  it "looks the charge up by reference after an ambiguous response instead of creating it again" do
    receivable = receivable_of("250.13")
    charge = request_charge(receivable)

    expect { submit(charge) }.to raise_error(Payments::Gateways::Errors::AmbiguousResponse)
    expect(reload_in_tenant(charge)).to have_attributes(status: "unknown", attempts: 1)

    simulator = Payments::Gateways::Simulator.new
    allow(Payments::Gateways::Simulator).to receive(:new).and_return(simulator)
    allow(simulator).to receive(:create_charge).and_call_original
    submit(charge)

    expect(simulator).not_to have_received(:create_charge)
    expect(reload_in_tenant(charge)).to have_attributes(status: "submitted", attempts: 2)
    expect(events(receivable)).to include("charge_unknown", "charge_submitted")
  end

  it "marks refused charges as failed and lets a new charge be requested" do
    receivable = receivable_of("90.66")
    charge = request_charge(receivable)

    submit(charge)

    expect(reload_in_tenant(charge)).to have_attributes(status: "failed", last_error: /recusada/)
    expect(request_charge(receivable).status).to eq("pending")
  end

  it "ignores charges that are no longer pending" do
    receivable = receivable_of("75.00")
    charge = request_charge(receivable)
    submit(charge)

    expect { submit(charge) }.not_to(change { reload_in_tenant(charge).attempts })
  end

  it "cancels a submitted charge at the provider when the receivable is canceled" do
    receivable = receivable_of("60.00")
    charge = request_charge(receivable)
    submit(charge)

    as_member(coordinator) { Receivables::Cancel.new(receivable:, reason: "Renegociado", actor: coordinator).call }
    run_dispatcher

    expect(reload_in_tenant(charge).status).to eq("canceled")
    expect(Payments::CancelRemoteChargeJob).to have_been_enqueued.with(organization.id, charge.id)
    perform_enqueued_jobs
  end

  it "records a confirmation for a canceled receivable without registering money" do
    receivable = receivable_of("60.00")
    charge = request_charge(receivable)
    submit(charge)
    as_member(coordinator) { Receivables::Cancel.new(receivable:, reason: "Renegociado", actor: coordinator).call }

    confirm(charge)

    expect(in_tenant(organization) { Payment.count }).to eq(0)
    expect(in_tenant(organization) { FinancialEvent.find_by!(kind: "charge_confirmed").details }).to include("attention")
  end

  describe Payments::SyncCharge do
    it "confirms charges the provider reports as paid and refreshes the others" do
      receivable = receivable_of("300.00")
      charge = request_charge(receivable)
      submit(charge)
      sync = -> { described_class.new(organization_id: organization.id, charge_id: charge.id).call }

      sync.call
      expect(reload_in_tenant(charge).last_synced_at).to be_present

      paid = Payments::Gateways::RemoteCharge.new(external_id: "x", status: "confirmed", payment_url: nil,
        paid_at: 1.hour.ago, amount: BigDecimal("300"))
      allow_any_instance_of(Payments::Gateways::Simulator).to receive(:find_charge).and_return(paid) # rubocop:disable RSpec/AnyInstance
      sync.call

      expect(reload_in_tenant(receivable).status).to eq("paid")
    end
  end

  describe Payments::SimulatePayment do
    it "is limited to submitted charges of the simulator" do
      receivable = receivable_of("40.00")
      charge = request_charge(receivable)

      expect { described_class.new(charge:, actor: coordinator).call }.to raise_error(Receivables::Errors::Invalid, /registrada/)
    end
  end

  describe Payments::ReconcileJob do
    it "schedules stale charges of every active organization" do
      receivable = receivable_of("50.00")
      charge = request_charge(receivable)
      submit(charge)
      in_tenant(organization) { charge.reload.update!(last_synced_at: 10.minutes.ago) }

      described_class.perform_now

      expect(Payments::SyncChargeJob).to have_been_enqueued.with(organization.id, charge.id)
    end
  end
end
