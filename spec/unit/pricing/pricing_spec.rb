# frozen_string_literal: true

RSpec.describe Pricing do
  describe Pricing::Amount do
    it "parses Brazilian and plain decimal notation without floats" do
      expect(described_class.parse("1.234,56")).to eq(BigDecimal("1234.56"))
      expect(described_class.parse("1234,5")).to eq(BigDecimal("1234.5"))
      expect(described_class.parse("1234.56")).to eq(BigDecimal("1234.56"))
      expect { described_class.parse("12a") }.to raise_error(Pricing::Amount::InvalidValue)
      expect { described_class.decimal(1.5) }.to raise_error(Pricing::Amount::InvalidValue, /Float/)
    end

    it "rounds money half up with two decimals" do
      expect(described_class.money("10.005")).to eq(BigDecimal("10.01"))
      expect(described_class.money("10.004")).to eq(BigDecimal("10.00"))
      expect(described_class.cost("3.33335")).to eq(BigDecimal("3.3334"))
      expect(described_class.quantity("1.0005")).to eq(BigDecimal("1.001"))
    end
  end

  describe Pricing::Line do
    it "computes the line total with fractional quantities" do
      line = described_class.build(quantity: "2.5", unit_price: "33.33", discount: "1.00", unit_cost: "20.1234")

      expect(line.gross).to eq(BigDecimal("83.33"))
      expect(line.total).to eq(BigDecimal("82.33"))
      expect(line.cost_total).to eq(BigDecimal("50.31"))
    end

    it "rejects invalid quantities, prices and discounts" do
      expect { described_class.build(quantity: "0", unit_price: "1") }.to raise_error(Pricing::Amount::InvalidValue, /quantity/)
      expect { described_class.build(quantity: "1", unit_price: "-1") }.to raise_error(Pricing::Amount::InvalidValue, /price/)
      expect { described_class.build(quantity: "1", unit_price: "10", discount: "11") }
        .to raise_error(Pricing::Amount::InvalidValue, /exceeds/)
      expect { described_class.build(quantity: "1", unit_price: "10", discount: "-1") }
        .to raise_error(Pricing::Amount::InvalidValue, /negative/)
    end
  end

  describe Pricing::Totals do
    let(:lines) do
      [Pricing::Line.build(quantity: 1, unit_price: "450.00", unit_cost: "180.0000"),
       Pricing::Line.build(quantity: "2", unit_price: "89.90", unit_cost: "41.5000")]
    end

    it "sums lines, applies the global discount and derives the margin" do
      totals = described_class.from(lines, discount: "29.80")

      expect(totals.subtotal).to eq(BigDecimal("629.80"))
      expect(totals.total).to eq(BigDecimal("600.00"))
      expect(totals.estimated_cost).to eq(BigDecimal("263.00"))
      expect(totals.margin).to eq(BigDecimal("337.00"))
      expect(totals.margin_percent).to eq(BigDecimal("56.2"))
    end

    it "leaves the margin unknown when any cost is unknown" do
      totals = described_class.from(lines + [Pricing::Line.build(quantity: 1, unit_price: 10)])

      expect(totals.estimated_cost).to be_nil
      expect(totals.margin_percent).to be_nil
    end

    it "rejects discounts above the subtotal or negative" do
      expect { described_class.from(lines, discount: "1000") }.to raise_error(Pricing::Amount::InvalidValue)
      expect { described_class.from(lines, discount: "-1") }.to raise_error(Pricing::Amount::InvalidValue)
    end

    it "handles empty documents" do
      totals = described_class.from([])

      expect(totals.total).to eq(0)
      expect(totals.margin_percent).to be_nil
    end
  end
end
