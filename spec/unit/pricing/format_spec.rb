# frozen_string_literal: true

RSpec.describe Pricing::Format do
  it "formats BRL with thousands separators and two decimals" do
    expect(described_class.brl(BigDecimal("1234567.5"))).to eq("R$ 1.234.567,50")
    expect(described_class.brl("0.1")).to eq("R$ 0,10")
    expect(described_class.brl(BigDecimal("-12"))).to eq("-R$ 12,00")
  end
end
