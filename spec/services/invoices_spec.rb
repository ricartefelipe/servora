# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:finance) { create(:membership, :finance, organization:) }

  def configure_fiscal(auto: false)
    in_tenant(organization) do
      FiscalSetting.create!(organization:, municipal_service_code: "14.01", iss_rate: "2.5", auto_issue_on_payment: auto,
        municipal_service_name: "Manutenção e conservação de máquinas e equipamentos")
    end
  end

  def receivable_of(amount)
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: amount)
    issue_receivable(scenario, work_order, amount)
  end

  def request_invoice(receivable) = as_member(finance) { Invoices::Request.new(receivable:, actor: finance).call }
  def submit(invoice) = Invoices::Submit.new(organization_id: organization.id, invoice_id: invoice.id).call

  it "requires fiscal settings and issues the NFS-e after commit" do
    receivable = receivable_of("800.00")
    expect { request_invoice(receivable) }.to raise_error(Servora::RuleViolation, /dados fiscais/)

    configure_fiscal
    invoice = request_invoice(receivable)
    run_dispatcher
    perform_enqueued_jobs(only: Invoices::SubmitJob)

    expect(reload_in_tenant(invoice)).to have_attributes(status: "authorized", amount: 800, number: be_present,
      verification_code: be_present)
    expect(invoice.description).to include(receivable.description)
    expect { request_invoice(receivable) }.to raise_error(Servora::RuleViolation, /nota fiscal válida/)
  end

  it "finds the invoice by reference after a lost response instead of issuing a second one" do
    configure_fiscal
    invoice = request_invoice(receivable_of("350.13"))

    expect { submit(invoice) }.to raise_error(Payments::Gateways::Errors::AmbiguousResponse)
    expect(reload_in_tenant(invoice).status).to eq("unknown")

    simulator = Payments::Gateways::Simulator.new
    allow(Payments::Gateways::Simulator).to receive(:new).and_return(simulator)
    allow(simulator).to receive(:issue_invoice).and_call_original
    submit(invoice)

    expect(simulator).not_to have_received(:issue_invoice)
    expect(reload_in_tenant(invoice).status).to eq("authorized")
  end

  it "records city hall rejections and allows a new request" do
    configure_fiscal
    receivable = receivable_of("120.66")
    rejected = request_invoice(receivable)

    submit(rejected)

    expect(reload_in_tenant(rejected)).to have_attributes(status: "error", last_error: /Prefeitura recusou/)
    expect(request_invoice(receivable).status).to eq("pending")
  end

  it "cancels issued invoices at the provider and pending ones locally" do
    configure_fiscal
    issued = request_invoice(receivable_of("200.00"))
    submit(issued)

    as_member(finance) { Invoices::Cancel.new(invoice: issued.reload, reason: "Valor incorreto", actor: finance).call }
    expect(reload_in_tenant(issued).status).to eq("canceling")
    run_dispatcher
    perform_enqueued_jobs(only: Invoices::CancelRemoteJob)
    expect(reload_in_tenant(issued).status).to eq("canceled")

    pending = request_invoice(receivable_of("90.00"))
    as_member(finance) { Invoices::Cancel.new(invoice: pending, reason: "Duplicada", actor: finance).call }
    expect(reload_in_tenant(pending).status).to eq("canceled")
  end

  it "issues automatically when a receivable is settled, once" do
    configure_fiscal(auto: true)
    receivable = receivable_of("450.00")
    pay(receivable, "200.00")
    run_dispatcher
    expect(in_tenant(organization) { ServiceInvoice.count }).to eq(0)

    pay(receivable, "250.00")
    2.times { run_dispatcher }

    expect(in_tenant(organization) { ServiceInvoice.where(receivable_id: receivable.id).count }).to eq(1)
  end

  it "follows invoices still processed by the city hall" do
    configure_fiscal
    invoice = request_invoice(receivable_of("75.00"))
    submit(invoice)
    in_tenant(organization) { invoice.reload.update!(status: "scheduled", last_synced_at: 10.minutes.ago) }

    Invoices::ReconcileJob.perform_now
    perform_enqueued_jobs(only: Invoices::SyncJob)

    expect(reload_in_tenant(invoice).status).to eq("authorized")
  end
end
