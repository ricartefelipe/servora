# frozen_string_literal: true

RSpec.describe Inventory::Balance do
  let(:empty) { described_class.empty }

  it "computes the moving average cost on entries with 4 decimals" do
    first, = empty.receive("10", "12.00")
    second, cost = first.receive("5", "15.3333")

    expect(first).to have_attributes(on_hand: BigDecimal("10"), average_cost: BigDecimal("12"))
    # (10 × 12.00 + 5 × 15.3333) / 15 = 13.11110 → 13.1111
    expect(second.average_cost).to eq(BigDecimal("13.1111"))
    expect(cost).to eq(BigDecimal("15.3333"))
  end

  it "keeps the average on outflows and prices them with the current average" do
    stock, = empty.receive("3", "10.00")
    stock, = stock.receive("1", "14.00")
    after, cost = stock.consume("2")

    expect(stock.average_cost).to eq(BigDecimal("11.0"))
    expect([after.on_hand, after.average_cost, cost]).to eq([BigDecimal("2"), BigDecimal("11.0"), BigDecimal("11.0")])
    expect(stock.outflow_cost("1.5")).to eq(BigDecimal("16.50"))
  end

  it "separates physical, reserved and available quantities" do
    stock, = empty.receive("5", "10")
    reserved, = stock.reserve("3")

    expect([reserved.on_hand, reserved.reserved, reserved.available]).to eq([5, 3, 2].map { |n| BigDecimal(n) })
    expect { reserved.reserve("2.001") }.to raise_error(Inventory::InsufficientAvailable, /available 2.0/)
    expect { reserved.consume("3") }.to raise_error(Inventory::InsufficientAvailable)

    consumed, = reserved.consume("3", from_reservation: true)
    expect([consumed.on_hand, consumed.reserved]).to eq([BigDecimal("2"), BigDecimal("0")])
  end

  it "never releases or consumes more than reserved and rejects non-positive quantities" do
    stock, = empty.receive("2", "10")
    reserved, = stock.reserve("1")

    expect { reserved.release("1.5") }.to raise_error(Inventory::InvalidQuantity)
    expect { reserved.consume("2", from_reservation: true) }.to raise_error(Inventory::InvalidQuantity)
    expect { stock.receive("0", "1") }.to raise_error(Inventory::InvalidQuantity)
    expect { stock.receive("1", "-1") }.to raise_error(Inventory::InvalidQuantity)
    expect(reserved.release("1").first.reserved).to eq(0)
  end

  it "rounds fractional quantities to 3 decimals" do
    stock, = empty.receive("1.23456", "10")

    expect(stock.on_hand).to eq(BigDecimal("1.235"))
  end
end
