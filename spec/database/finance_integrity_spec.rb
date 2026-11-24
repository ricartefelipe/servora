# frozen_string_literal: true

require "rails_helper"

# Database guarantees of receivables, independent of the use cases.
RSpec.describe "Finance integrity in PostgreSQL" do
  def in_savepoint(&)
    ActiveRecord::Base.transaction(requires_new: true, &)
  end

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let!(:work_order) { open_work_order(scenario) }
  let!(:receivable) do
    add_authorized_item(scenario, work_order, unit_price: "500")
    issue_receivable(scenario, work_order, "500")
  end

  def expect_violation(constraint, &)
    in_tenant(organization) do
      expect { in_savepoint(&) }.to raise_error(ActiveRecord::StatementInvalid, /#{constraint}/)
    end
  end

  it "keeps payments within the net amount and refunds within payments" do
    expect_violation("receivables_values") { Receivable.where(id: receivable.id).update_all(paid_amount: 501) }
    expect_violation("receivables_values") { Receivable.where(id: receivable.id).update_all(refunded_amount: 1) }
    expect_violation("receivables_values") { Receivable.where(id: receivable.id).update_all(discount_amount: 600) }
  end

  it "keeps statuses consistent with the amounts" do
    expect_violation("receivables_status_consistency") { Receivable.where(id: receivable.id).update_all(status: "paid") }
    expect_violation("receivables_status_consistency") do
      Receivable.where(id: receivable.id).update_all(status: "canceled", canceled_at: Time.current, paid_amount: 10)
    end
  end

  it "requires the receivable customer to be the work order customer" do
    other = create(:customer, organization:)

    expect_violation("fk_receivables_work_order_customer") do
      Receivable.where(id: receivable.id).update_all(customer_id: other.id)
    end
  end

  it "keeps the financial history append-only" do
    expect_violation("permission denied") { FinancialEvent.where(receivable_id: receivable.id).update_all(amount: 1) }
    expect_violation("permission denied") { FinancialEvent.where(receivable_id: receivable.id).delete_all }
  end

  it "allows one charge in flight per receivable" do
    in_tenant(organization) do
      attributes = { organization_id: organization.id, receivable_id: receivable.id, provider: "simulator", billing_type: "pix",
                     amount: 500, due_on: Time.zone.today }
      PaymentCharge.create!(attributes.merge(external_reference: "a"))

      expect { in_savepoint { PaymentCharge.create!(attributes.merge(external_reference: "b")) } }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it "hides receivables and payments from other organizations" do
    pay(receivable, "100")

    in_tenant(create(:organization)) do
      expect([Receivable, Payment, FinancialEvent, PaymentCharge, Expense, PaymentIntegration].map(&:count)).to all(eq(0))
    end
  end

  it "stores the provider API key encrypted" do
    in_tenant(organization) do
      PaymentIntegration.create!(organization:, provider: "asaas", api_key: "chave-secreta-sandbox")
      raw = PaymentIntegration.connection.select_value("SELECT api_key FROM payment_integrations")

      expect(raw).not_to include("chave-secreta-sandbox")
      expect(PaymentIntegration.sole.api_key).to eq("chave-secreta-sandbox")
    end
  end
end
