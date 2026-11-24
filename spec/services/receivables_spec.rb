# frozen_string_literal: true

require "rails_helper"

RSpec.describe Receivables do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }
  let!(:work_order) { open_work_order(scenario) }

  before { add_authorized_item(scenario, work_order, unit_price: "1000.00", unit_cost: "400") }

  describe Receivables::Issue do
    it "numbers the receivable, records the history and limits billing to the authorized total" do
      first = issue_receivable(scenario, work_order, "600")
      second = issue_receivable(scenario, work_order, "400")

      expect([first.number, second.number]).to all(match(/\AFAT-\d{4}-0000\d\z/))
      expect(in_tenant(organization) { FinancialEvent.where(kind: "issued").count }).to eq(2)
      expect { issue_receivable(scenario, work_order, "0.01") }
        .to raise_error(Receivables::Errors::Invalid, /saldo a faturar da ordem \(R\$ 0,00\)/)
    end

    it "refuses past due dates and canceled work orders" do
      expect { issue_receivable(scenario, work_order, "10", due_on: Time.zone.yesterday) }
        .to raise_error(Receivables::Errors::Invalid, /anterior a hoje/)

      as_member(coordinator) { WorkOrders::Cancel.new(work_order:, actor: coordinator, reason: "Desistência").call }
      expect { issue_receivable(scenario, work_order, "10") }.to raise_error(Receivables::Errors::Invalid, /cancelada/)
    end
  end

  describe Receivables::RegisterPayment do
    let(:receivable) { issue_receivable(scenario, work_order, "1000") }

    it "accepts partial payments until the receivable is settled" do
      pay(receivable, "300")
      pay(receivable, "700")

      expect(reload_in_tenant(receivable)).to have_attributes(status: "paid", paid_amount: 1000)
      expect(receivable.settled_at).to be_present
      expect { pay(receivable, "0.01") }.to raise_error(Receivables::Errors::Invalid, /supera o saldo/)
    end

    it "records a payment once per idempotency key" do
      key = SecureRandom.uuid_v7

      first = pay(receivable, "250", key:)

      expect(pay(receivable, "250", key:)).to eq(first)
      expect(reload_in_tenant(receivable).paid_amount).to eq(250)
      expect { pay(receivable, "100", key:) }.to raise_error(IdempotentOperation::KeyReused)
    end

    it "refuses invalid methods and future dates" do
      expect { pay(receivable, "10", method: "crypto") }.to raise_error(Receivables::Errors::Invalid, /Forma de pagamento/)
      expect do
        in_tenant(organization) do
          described_class.new(receivable:, amount: "10", payment_method: "pix", actor: nil, paid_at: 1.day.from_now).call
        end
      end.to raise_error(Receivables::Errors::Invalid, /futuro/)
    end
  end

  describe "discounts, refunds and cancellation" do
    let(:receivable) { issue_receivable(scenario, work_order, "1000") }

    def as_coordinator(&) = as_member(coordinator, &)

    it "grants a discount with reason and settles the remaining balance" do
      pay(receivable, "900")
      as_coordinator { Receivables::GrantDiscount.new(receivable:, amount: "100", reason: "Fidelidade", actor: coordinator).call }

      expect(reload_in_tenant(receivable)).to have_attributes(status: "paid", discount_amount: 100)
      expect do
        as_coordinator { Receivables::GrantDiscount.new(receivable:, amount: "1", reason: " ", actor: coordinator).call }
      end.to raise_error(Receivables::Errors::Invalid, /motivo/)
    end

    it "refunds within the payment and reopens the balance" do
      payment = pay(receivable, "1000")
      as_coordinator { Receivables::RefundPayment.new(payment:, amount: "200", reason: "Serviço parcial", actor: coordinator).call }

      expect(reload_in_tenant(receivable)).to have_attributes(status: "partially_paid", refunded_amount: 200)
      expect(reload_in_tenant(payment).refundable).to eq(800)
      expect do
        as_coordinator { Receivables::RefundPayment.new(payment:, amount: "900", reason: "x", actor: coordinator).call }
      end.to raise_error(Receivables::Errors::Invalid, /estornável \(R\$ 800,00\)/)
    end

    it "cancels only without money kept and releases the amount to be billed again" do
      payment = pay(receivable, "100")
      cancel = -> { as_coordinator { Receivables::Cancel.new(receivable:, reason: "Emitida errada", actor: coordinator).call } }

      expect(&cancel).to raise_error(Receivables::Errors::Invalid, /Estorne os pagamentos/)
      as_coordinator { Receivables::RefundPayment.new(payment:, amount: "100", reason: "Devolução", actor: coordinator).call }
      cancel.call

      expect(reload_in_tenant(receivable)).to have_attributes(status: "canceled", cancel_reason: "Emitida errada")
      expect(in_tenant(organization) { WorkOrderFinancialsQuery.new(work_order).remaining_to_bill }).to eq(1000)
      expect { pay(receivable, "1") }.to raise_error(Receivables::Errors::Invalid, /cancelada/)
    end
  end

  describe WorkOrderFinancialsQuery do
    it "compares predicted and realized margin with historical costs" do
      warehouse = create(:warehouse, organization:)
      part = stock_part(organization)
      receive_stock(warehouse, part, "2", "50")
      as_member(coordinator) do
        Inventory::Consume.new(work_order:, warehouse:, item: part, quantity: "2", actor: coordinator).call
        Expense.create!(organization:, work_order:, category: "toll", description: "Pedágio", amount: "12.40",
          incurred_on: Time.zone.today)
      end
      receivable = issue_receivable(scenario, work_order, "1000")
      as_member(coordinator) { Receivables::GrantDiscount.new(receivable:, amount: "50", reason: "Pontualidade", actor: nil).call }

      query = in_tenant(organization) { described_class.new(work_order) }
      predicted = in_tenant(organization) { query.predicted }
      realized = in_tenant(organization) { query.realized }

      expect([predicted.total, predicted.margin]).to eq([BigDecimal("1000"), BigDecimal("600")])
      expect([realized.revenue, realized.material_cost, realized.expenses, realized.margin])
        .to eq([BigDecimal("950"), BigDecimal("100"), BigDecimal("12.40"), BigDecimal("837.60")])
    end
  end
end
