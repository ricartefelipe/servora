# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks do
  include ActiveJob::TestHelper

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:public_ip) { "203.0.113.10" }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with("erp.exemplo.com.br").and_return([public_ip])
  end

  def create_endpoint(url: "https://erp.exemplo.com.br/hooks", events: ["work_order.created"])
    in_tenant(organization) { Integrations::CreateEndpoint.new(organization:, url:, events:).call }
  end

  def deliver(delivery) = Webhooks::Deliver.new(organization_id: organization.id, delivery_id: delivery.id).call
  def deliveries = in_tenant(organization) { WebhookDelivery.order(:created_at).to_a }

  describe Webhooks::SafeUrl do
    it "accepts public HTTPS hosts and refuses internal networks, plain HTTP, credentials and custom ports" do
      allow(Resolv).to receive(:getaddresses).with("interno.exemplo").and_return(["10.0.0.7"])
      allow(Resolv).to receive(:getaddresses).with("metadados.exemplo").and_return(["169.254.169.254"])

      expect(described_class.check!("https://erp.exemplo.com.br/hooks").address).to eq(public_ip)
      unsafe = ["https://interno.exemplo/x", "https://metadados.exemplo/", "http://erp.exemplo.com.br/x",
                "https://user:senha@erp.exemplo.com.br/x", "https://erp.exemplo.com.br:8443/x", "https://127.0.0.1/x", "nada"]
      unsafe.each do |url|
        expect { described_class.check!(url) }.to raise_error(described_class::Unsafe), url
      end
    end
  end

  it "fans out once per endpoint and event, signs the body and marks the delivery as delivered" do
    _endpoint, secret = create_endpoint
    stub = stub_request(:post, "https://erp.exemplo.com.br/hooks").to_return(status: 204)
    open_work_order(scenario)

    2.times { run_dispatcher }
    expect(deliveries.size).to eq(1)
    perform_enqueued_jobs

    delivery = deliveries.first
    expect(delivery).to have_attributes(status: "delivered", attempts: 1)
    expect(stub.with do |request|
      timestamp, signature = request.headers["Servora-Signature"].scan(/t=(\d+),v1=(\h+)/).first
      request.headers["Servora-Event-Id"] == delivery.event_id &&
        Webhooks::Deliver.signature(secret, timestamp, request.body) == signature
    end).to have_been_requested.once
  end

  it "retries failures and gives up after the attempt limit" do
    create_endpoint
    stub_request(:post, "https://erp.exemplo.com.br/hooks").to_return(status: 503)
    open_work_order(scenario)
    run_dispatcher
    delivery = deliveries.first

    expect { deliver(delivery) }.to raise_error(Webhooks::Deliver::Retry)
    expect(deliveries.first).to have_attributes(status: "pending", last_response_code: 503)

    in_tenant(organization) { delivery.reload.update!(attempts: Webhooks::Deliver::MAX_ATTEMPTS - 1) }
    deliver(delivery)
    expect(deliveries.first.status).to eq("failed")
  end

  it "does not follow redirects and refuses addresses that became internal" do
    create_endpoint
    stub_request(:post, "https://erp.exemplo.com.br/hooks").to_return(status: 302,
      headers: { "Location" => "https://127.0.0.1/" })
    open_work_order(scenario)
    run_dispatcher
    delivery = deliveries.first

    expect { deliver(delivery) }.to raise_error(Webhooks::Deliver::Retry)
    allow(Resolv).to receive(:getaddresses).with("erp.exemplo.com.br").and_return(["192.168.0.10"])
    deliver(delivery)

    expect(deliveries.first).to have_attributes(status: "failed", last_error: /URL recusada/)
    expect(a_request(:post, "https://127.0.0.1/")).not_to have_been_made
  end

  it "rejects endpoints pointing to internal networks on save" do
    allow(Resolv).to receive(:getaddresses).with("intranet.local").and_return(["192.168.1.2"])

    expect { create_endpoint(url: "https://intranet.local/x") }.to raise_error(ActiveRecord::RecordInvalid, /rede interna/)
  end

  describe "payment notifications" do
    def notify(payload) = Webhooks::ReceivePaymentNotification.new(organization_id: organization.id, payload:).call

    it "stores each provider event once and confirms the referenced charge" do
      work_order = open_work_order(scenario)
      add_authorized_item(scenario, work_order, unit_price: "210.00")
      receivable = issue_receivable(scenario, work_order, "210.00")
      charge = as_member(scenario[:coordinator]) { Payments::RequestCharge.new(receivable:, actor: nil).call }
      payload = { "id" => "evt_001", "event" => "PAYMENT_RECEIVED",
                  "payment" => { "externalReference" => charge.external_reference, "paymentDate" => "2026-11-20" } }

      expect([notify(payload), notify(payload)]).to eq(%i[accepted duplicate])
      run_dispatcher
      perform_enqueued_jobs(only: Webhooks::ProcessInboundJob)

      expect(reload_in_tenant(receivable).status).to eq("paid")
      expect(in_tenant(organization) { InboundWebhook.sole.status }).to eq("processed")
    end

    it "keeps unrelated events as ignored" do
      notify({ "id" => "evt_002", "event" => "PAYMENT_CREATED", "payment" => {} })
      run_dispatcher
      perform_enqueued_jobs(only: Webhooks::ProcessInboundJob)

      expect(in_tenant(organization) { InboundWebhook.sole.status }).to eq("ignored")
    end
  end
end
