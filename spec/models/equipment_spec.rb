# frozen_string_literal: true

require "rails_helper"

RSpec.describe Equipment do
  let(:location) { create(:service_location) }

  it "requires the location to belong to the owner customer" do
    other_location = create(:service_location, customer: create(:customer, organization: location.organization))
    equipment = build(:equipment, location:, service_location: other_location, customer: location.customer)

    expect(in_tenant(location.organization) { equipment.valid? }).to be(false)
    expect(equipment.errors[:service_location]).to include("deve pertencer ao cliente proprietário")
  end

  it "rejects warranty before installation and knows when it is under warranty" do
    equipment = build(:equipment, location:, installed_on: Date.new(2026, 5, 1), warranty_until: Date.new(2026, 4, 1))

    expect(in_tenant(location.organization) { equipment.valid? }).to be(false)
    equipment.warranty_until = Date.new(2027, 5, 1)
    expect(equipment.under_warranty?(on: Date.new(2026, 11, 24))).to be(true)
    expect(equipment.under_warranty?(on: Date.new(2027, 6, 1))).to be(false)
  end
end
