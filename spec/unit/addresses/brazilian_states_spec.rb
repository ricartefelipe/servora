# frozen_string_literal: true

RSpec.describe Addresses::BrazilianStates do
  it "validates federative units case-insensitively" do
    expect(described_class.valid?("sp")).to be(true)
    expect(described_class.valid?("XX")).to be(false)
  end

  it "normalizes and formats postal codes" do
    expect(described_class.normalize_postal_code("01310-100")).to eq("01310100")
    expect(described_class.normalize_postal_code("")).to be_nil
    expect(described_class.format_postal_code("01310100")).to eq("01310-100")
    expect(described_class.format_postal_code("123")).to eq("123")
  end
end
