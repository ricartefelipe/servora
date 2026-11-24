# frozen_string_literal: true

RSpec.describe Quotes do
  describe Quotes::VersionStates do
    it "allows the documented lifecycle and rejects shortcuts" do
      expect(described_class.allowed?(:draft, :sent)).to be(true)
      expect(described_class.allowed?(:sent, :approved)).to be(true)
      expect(described_class.allowed?(:approved, :superseded)).to be(true)
      expect(described_class.allowed?(:draft, :approved)).to be(false)
      expect(described_class.allowed?(:approved, :rejected)).to be(false)
      expect(described_class.terminal?(:superseded)).to be(true)
    end

    it "raises a descriptive error for invalid transitions" do
      expect { described_class.assert!(:rejected, :approved) }
        .to raise_error(StateMachines::Definition::InvalidTransition, "transition rejected -> approved is not allowed")
    end
  end

  describe Quotes::ContentDigest do
    it "is independent of key order and sensitive to content" do
      first = { "items" => [{ "price" => BigDecimal("10.00"), "qty" => 1 }], "total" => BigDecimal("10") }
      reordered = { total: BigDecimal("10"), items: [{ qty: 1, price: BigDecimal("10.00") }] }
      changed = first.merge("total" => BigDecimal("11"))

      expect(described_class.call(first)).to eq(described_class.call(reordered))
      expect(described_class.call(first)).not_to eq(described_class.call(changed))
      expect(described_class.call(valid_until: Date.new(2026, 12, 1))).to match(/\A\h{64}\z/)
    end
  end
end
