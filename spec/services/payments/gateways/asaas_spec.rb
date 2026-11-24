# frozen_string_literal: true

require "rails_helper"

# Contract of the Asaas adapter against recorded request/response shapes.
# No real network access: every request is stubbed with WebMock.
RSpec.describe Payments::Gateways::Asaas do
  subject(:gateway) { described_class.new(api_key: "chave-sandbox", base_url: base) }

  let(:base) { "https://asaas.test/v3" }
  let(:customer) do
    instance_double(Customer, id: "0193c000-0000-7000-8000-000000000001", name: "Mercado Bom Preço",
      document: "11.222.333/0001-81", email: "financeiro@bompreco.test")
  end
  let(:charge) do
    instance_double(PaymentCharge, external_reference: "srv-ref-1", billing_type: "pix", amount: BigDecimal("150.00"),
      due_on: Date.new(2026, 12, 10), external_id: "pay_123")
  end
  let(:json) { { "Content-Type" => "application/json" } }

  def stub_customer_lookup(data)
    stub_request(:get, "#{base}/customers?externalReference=#{customer.id}")
      .with(headers: { "access_token" => "chave-sandbox" })
      .to_return(status: 200, body: { data: }.to_json, headers: json)
  end

  it "creates the customer when missing and the charge with our external reference" do
    stub_customer_lookup([])
    create_customer = stub_request(:post, "#{base}/customers")
      .with(body: hash_including("cpfCnpj" => "11222333000181", "externalReference" => customer.id))
      .to_return(status: 200, body: { id: "cus_9" }.to_json, headers: json)
    create_payment = stub_request(:post, "#{base}/payments")
      .with(body: hash_including("customer" => "cus_9", "billingType" => "PIX", "value" => "150.0", "dueDate" => "2026-12-10",
        "externalReference" => "srv-ref-1"))
      .to_return(status: 200, body: { id: "pay_123", status: "PENDING", invoiceUrl: "https://asaas.test/i/pay_123" }.to_json,
        headers: json)

    remote = gateway.create_charge(charge, customer)

    expect(remote).to have_attributes(external_id: "pay_123", status: "submitted", payment_url: "https://asaas.test/i/pay_123")
    expect([create_customer, create_payment]).to all(have_been_requested.once)
  end

  it "reuses an existing customer and finds charges by external reference" do
    stub_customer_lookup([{ id: "cus_1" }])
    stub_request(:post, "#{base}/payments").with(body: hash_including("customer" => "cus_1"))
      .to_return(status: 200, body: { id: "pay_1", status: "PENDING" }.to_json, headers: json)
    stub_request(:get, "#{base}/payments?externalReference=srv-ref-1")
      .to_return(status: 200, headers: json,
        body: { data: [{ id: "pay_1", status: "RECEIVED", value: 150, paymentDate: "2026-12-05" }] }.to_json)

    gateway.create_charge(charge, customer)
    found = gateway.find_charge(charge)

    expect(found).to have_attributes(external_id: "pay_1", status: "confirmed", amount: BigDecimal("150"))
    expect(found.paid_at.to_date).to eq(Date.new(2026, 12, 5))
  end

  it "returns nil when the provider has no charge with the reference" do
    stub_request(:get, "#{base}/payments?externalReference=srv-ref-1")
      .to_return(status: 200, body: { data: [] }.to_json, headers: json)

    expect(gateway.find_charge(charge)).to be_nil
  end

  it "classifies failures by whether the request may have been processed" do
    stub_customer_lookup([{ id: "cus_1" }])
    payments = "#{base}/payments"

    stub_request(:post, payments).to_timeout
    expect { gateway.create_charge(charge, customer) }.to raise_error(Payments::Gateways::Errors::Unavailable)

    stub_request(:post, payments).to_raise(Net::ReadTimeout)
    expect { gateway.create_charge(charge, customer) }.to raise_error(Payments::Gateways::Errors::AmbiguousResponse)

    stub_request(:post, payments).to_return(status: 502, body: "")
    expect { gateway.create_charge(charge, customer) }.to raise_error(Payments::Gateways::Errors::AmbiguousResponse)

    stub_request(:post, payments).to_return(status: 429, body: "")
    expect { gateway.create_charge(charge, customer) }.to raise_error(Payments::Gateways::Errors::Unavailable)
  end

  it "reports provider validation messages and rejected credentials" do
    stub_customer_lookup([{ id: "cus_1" }])
    stub_request(:post, "#{base}/payments").to_return(status: 400, headers: json,
      body: { errors: [{ code: "invalid_value", description: "O valor deve ser maior que R$ 5,00." }] }.to_json)
    expect { gateway.create_charge(charge, customer) }.to raise_error(Payments::Gateways::Errors::Rejected, /maior que R\$ 5,00/)

    stub_request(:delete, "#{base}/payments/pay_123").to_return(status: 401, body: "")
    expect { gateway.cancel_charge(charge) }.to raise_error(Payments::Gateways::Errors::Rejected, /Credencial/)
  end

  it "requests refunds for the provider charge with our identification" do
    refund = instance_double(PaymentRefund, id: "0193c000-0000-7000-8000-0000000000ff", amount: BigDecimal("75.50"))
    stub = stub_request(:post, "#{base}/payments/pay_123/refund")
      .with(body: hash_including("value" => "75.5", "description" => "Estorno Servora #{refund.id}"))
      .to_return(status: 200, body: { id: "pay_123", status: "REFUNDED" }.to_json, headers: json)

    expect(gateway.refund_charge(charge, refund)).to have_attributes(external_id: "pay_123", status: "accepted")
    expect(stub).to have_been_requested.once
  end

  describe "NFS-e" do
    let(:invoice) do
      instance_double(ServiceInvoice, external_reference: "srv-nfse-1", amount: BigDecimal("800.00"), description: "Manutenção",
        external_id: "inv_1")
    end
    let(:settings) do
      instance_double(FiscalSetting, municipal_service_code: "14.01", municipal_service_name: "Manutenção de equipamentos",
        iss_rate: BigDecimal("2.5"), retain_iss: false)
    end
    let(:paid_charge) { instance_double(PaymentCharge, external_id: "pay_123") }

    it "creates the invoice linked to the provider payment and authorizes it" do
      create = stub_request(:post, "#{base}/invoices")
        .with(body: hash_including("payment" => "pay_123", "externalReference" => "srv-nfse-1", "value" => "800.0",
          "municipalServiceCode" => "14.01", "taxes" => hash_including("iss" => "2.5", "retainIss" => false)))
        .to_return(status: 200, body: { id: "inv_1", status: "SCHEDULED" }.to_json, headers: json)
      stub_request(:post, "#{base}/invoices/inv_1/authorize")
        .to_return(status: 200, headers: json, body: { id: "inv_1", status: "AUTHORIZED", number: "1234", validationCode: "AB-12",
                                                       pdfUrl: "https://asaas.test/nfse/inv_1.pdf" }.to_json)

      remote = gateway.issue_invoice(invoice, customer, settings, paid_charge)

      expect(remote).to have_attributes(status: "authorized", number: "1234", verification_code: "AB-12",
        pdf_url: "https://asaas.test/nfse/inv_1.pdf")
      expect(create).to have_been_requested.once
    end

    it "finds invoices by external reference and maps provider errors" do
      stub_request(:get, "#{base}/invoices?externalReference=srv-nfse-1")
        .to_return(status: 200, headers: json,
          body: { data: [{ id: "inv_1", status: "ERROR", statusDescription: "Código de serviço inválido" }] }.to_json)

      expect(gateway.find_invoice(invoice)).to have_attributes(status: "error", message: "Código de serviço inválido")
    end
  end

  it "requires the customer document to create customers" do
    stub_customer_lookup([])
    allow(customer).to receive(:document).and_return(nil)

    expect { gateway.create_charge(charge, customer) }.to raise_error(Payments::Gateways::Errors::Rejected, /CPF ou CNPJ/)
  end
end
