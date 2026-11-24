# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Equipment" do
  let(:organization) { create(:organization) }
  let(:coordinator) { create(:membership, :coordinator, organization:) }
  let(:customer) { create(:customer, organization:) }
  let!(:location) { create(:service_location, customer:) }

  it "registers equipment and shows its history" do
    sign_in_as(coordinator)

    post equipment_index_path, params: { equipment: { customer_id: customer.id, service_location_id: location.id,
                                                      equipment_type: "Chiller", manufacturer: "Frio", serial_number: "x-1" } }

    equipment = in_tenant(organization) { Equipment.sole }
    follow_redirect!
    expect(response.body).to include("Chiller", "Cadastrado")
    expect(equipment.serial_number).to eq("X-1")
  end

  it "refuses a customer from another organization in the form" do
    foreign = create(:customer)
    sign_in_as(coordinator)

    post equipment_index_path,
      params: { equipment: { customer_id: foreign.id, service_location_id: location.id, equipment_type: "X" } }

    expect(response).to have_http_status(:not_found)
  end

  it "lists the locations of the selected customer for the dependent select" do
    other = create(:service_location, customer:, name: "Depósito")
    sign_in_as(coordinator)

    get options_customer_locations_path(customer)

    expect(response.body).to include(location.name, other.name, 'id="location-options"')
  end

  it "relocates through the dedicated action and records the transfer" do
    equipment = create(:equipment, location:)
    target = create(:service_location, customer: create(:customer, organization:), name: "Nova sede")
    sign_in_as(coordinator)

    patch relocate_equipment_path(equipment), params: { relocation: { service_location_id: target.id, reason: "Venda" } }

    in_tenant(organization) do
      expect(equipment.reload.service_location_id).to eq(target.id)
      expect(EquipmentEvent.where(equipment_id: equipment.id).pluck(:kind)).to include("ownership_transferred")
    end
  end

  it "changes the operational status" do
    equipment = create(:equipment, location:)
    sign_in_as(coordinator)

    patch change_status_equipment_path(equipment), params: { status_change: { operational_status: "attention", reason: "Ruído" } }

    expect(in_tenant(organization) { equipment.reload.operational_status }).to eq("attention")
  end

  it "does not let finance change equipment" do
    equipment = create(:equipment, location:)
    sign_in_as(create(:membership, :finance, organization:))

    patch archive_equipment_path(equipment)

    expect(response).to have_http_status(:forbidden)
  end
end
