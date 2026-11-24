# frozen_string_literal: true

require "rails_helper"

RSpec.describe EquipmentCatalog::SearchQuery do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, name: "Mercado Sol") }
  let(:location) { create(:service_location, customer:) }

  before do
    create(:equipment, location:, equipment_type: "Chiller", serial_number: "CH-1", operational_status: "inoperative")
    create(:equipment, location:, equipment_type: "Split", serial_number: "SP-1", archived_at: Time.current)
    create(:equipment, location: create(:service_location, customer: create(:customer, organization:)), equipment_type: "Cassete")
  end

  def types(**filters)
    in_tenant(organization) { described_class.new(Equipment.all, **filters).call.map(&:equipment_type) }
  end

  it "filters by archive and operational status" do
    expect(types).to contain_exactly("Chiller", "Cassete")
    expect(types(include_archived: true)).to contain_exactly("Chiller", "Split", "Cassete")
    expect(types(status: "inoperative")).to eq(["Chiller"])
    expect(types(status: "desconhecido")).to contain_exactly("Chiller", "Cassete")
  end

  it "filters by customer and free text" do
    expect(types(customer_id: customer.id)).to eq(["Chiller"])
    expect(types(term: "mercado")).to eq(["Chiller"])
    expect(types(term: "ch-1")).to eq(["Chiller"])
  end
end
