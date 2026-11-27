# frozen_string_literal: true

RSpec.describe Reports::Percent do
  it "keeps the share with one decimal, rounding half up" do
    expect(described_class.of(2, 3).value).to eq(BigDecimal("66.7"))
    expect(described_class.of(1, 8).value).to eq(BigDecimal("12.5"))
    expect(described_class.of(3, 3).value).to eq(BigDecimal("100"))
  end

  it "is absent without a total" do
    expect(described_class.of(0, 0)).to be_nil
  end
end
