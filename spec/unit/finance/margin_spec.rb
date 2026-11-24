# frozen_string_literal: true

RSpec.describe Finance::Margin do
  it "computes margin and percentage over revenue" do
    margin = described_class.build(revenue: "1200", material_cost: "310.40", labor_cost: "187.50", expenses: "42")

    expect([margin.total_cost, margin.margin, margin.margin_percent]).to eq([BigDecimal("539.90"), BigDecimal("660.10"),
                                                                             BigDecimal("55.0")])
  end

  it "has no percentage without revenue and allows negative margins" do
    expect(described_class.build(revenue: "0", expenses: "10").margin_percent).to be_nil
    expect(described_class.build(revenue: "100", labor_cost: "150").margin_percent).to eq(BigDecimal("-50.0"))
  end
end
