# frozen_string_literal: true

RSpec.describe Reports::CsvCell do
  it "neutralizes formula triggers and formats values" do
    expect(['=HYPERLINK("x")', "+1", "-2", "@cmd", "\tx", "Normal"].map { |value| described_class.safe(value) })
      .to eq(["'=HYPERLINK(\"x\")", "'+1", "'-2", "'@cmd", "'\tx", "Normal"])
    expect([BigDecimal("10.50"), 3, nil, Date.new(2026, 11, 24)].map { |value| described_class.safe(value) })
      .to eq(["10.5", "3", "", "2026-11-24"])
    expect(described_class.safe(Reports::Money.of("1234.5"))).to eq("1234.5")
  end
end
