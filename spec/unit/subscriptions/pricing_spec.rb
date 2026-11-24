# frozen_string_literal: true

RSpec.describe Subscriptions::Pricing do
  let(:pricing) do
    described_class.new(plan_price: BigDecimal("590"), included_technicians: 10, extra_technician_price: BigDecimal("35"),
      plan_modules: %w[inventory preventive], module_prices: { "inventory" => BigDecimal("120"), "preventive" => BigDecimal("90"),
                                                               "finance" => BigDecimal("150"), "api" => BigDecimal("200") })
  end

  it "charges extra seats and add-ons not included in the plan" do
    expect(pricing.monthly_amount(seats: 12, addons: %w[finance inventory desconhecido])).to eq(BigDecimal("810.00"))
    expect(pricing.modules(%w[finance inventory])).to eq(%w[finance inventory preventive])
  end

  it "does not discount unused seats and requires at least one" do
    expect(pricing.monthly_amount(seats: 2, addons: [])).to eq(BigDecimal("590.00"))
    expect { pricing.monthly_amount(seats: 0, addons: []) }.to raise_error(ArgumentError)
  end
end
