# frozen_string_literal: true

RSpec.describe Receivables::Position do
  let(:position) { described_class.issue("1000.00") }

  it "tracks partial payments, discounts and refunds" do
    paid = position.pay("400").grant_discount("100")

    expect([paid.net_amount, paid.net_paid, paid.balance, paid.status]).to eq([BigDecimal("900"), BigDecimal("400"),
                                                                               BigDecimal("500"), "partially_paid"])
    settled = paid.pay("500")
    expect([settled.balance, settled.status, settled.settled?]).to eq([BigDecimal("0"), "paid", true])
    reopened = settled.refund("50", refundable: BigDecimal("500"))
    expect([reopened.balance, reopened.status]).to eq([BigDecimal("50"), "partially_paid"])
  end

  it "refuses overpayment, excessive discounts and refunds with explicit amounts" do
    paid = position.pay("300")

    expect do
      paid.pay("700.01")
    end.to raise_error(Receivables::Rejected, "O pagamento (R$ 700,01) supera o saldo em aberto (R$ 700,00).")
    expect { paid.grant_discount("800") }.to raise_error(Receivables::Rejected, /desconto \(R\$ 800,00\)/)
    expect do
      paid.refund("200", refundable: BigDecimal("150"))
    end.to raise_error(Receivables::Rejected, /estornável \(R\$ 150,00\)/)
    expect { paid.pay("0") }.to raise_error(Receivables::Rejected, /maior que zero/)
  end

  it "only allows cancellation without money kept" do
    expect { position.ensure_cancelable! }.not_to raise_error
    expect { position.pay("10").ensure_cancelable! }.to raise_error(Receivables::Rejected, /Estorne os pagamentos \(R\$ 10,00\)/)
    expect { position.pay("10").refund("10", refundable: BigDecimal("10")).ensure_cancelable! }.not_to raise_error
  end

  it "rejects non-positive amounts and rounds half up to cents" do
    expect { described_class.issue("0") }.to raise_error(Receivables::Rejected)
    expect(described_class.issue("10.005").amount).to eq(BigDecimal("10.01"))
  end
end
