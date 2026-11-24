# frozen_string_literal: true

require "rails_helper"

RSpec.describe EquipmentLifecycle do
  let(:organization) { create(:organization) }
  let(:actor) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:matriz) { create(:service_location, customer:, name: "Matriz") }
  let(:filial) { create(:service_location, customer:, name: "Filial") }
  let(:equipment) do
    as_member(actor) do
      EquipmentLifecycle::Register.new(organization:, actor:,
        attributes: { customer_id: customer.id, service_location_id: matriz.id, equipment_type: "Cassete",
                      serial_number: "abc1" }).call
    end
  end

  describe EquipmentLifecycle::Register do
    it "registers with a history entry and normalized identifiers" do
      in_tenant(organization) do
        expect(equipment.reload.serial_number).to eq("ABC1")
        expect(equipment.events.map(&:kind)).to eq(["registered"])
      end
    end
  end

  describe EquipmentLifecycle::Relocate do
    it "records a relocation within the same customer" do
      as_member(actor) { described_class.new(equipment:, location: filial, actor:, reason: "Reforma").call }

      in_tenant(organization) do
        event = equipment.events.first
        expect(event).to have_attributes(kind: "relocated", from_location_id: matriz.id, to_location_id: filial.id,
          description: "Reforma")
      end
    end

    it "records an ownership transfer and keeps the previous owner in history" do
      buyer_location = create(:service_location, customer: create(:customer, organization:))

      as_member(actor) { described_class.new(equipment:, location: buyer_location, actor:).call }

      in_tenant(organization) do
        expect(equipment.reload.customer_id).to eq(buyer_location.customer_id)
        expect(equipment.events.first).to have_attributes(kind: "ownership_transferred", from_customer_id: customer.id,
          to_customer_id: buyer_location.customer_id)
      end
    end

    it "rejects moves based on a stale version" do
      stale_version = in_tenant(organization) { equipment.lock_version }
      as_member(actor) { described_class.new(equipment:, location: filial, actor:).call }

      expect do
        as_member(actor) do
          described_class.new(equipment: equipment.reload, location: matriz, actor:, expected_version: stale_version).call
        end
      end.to raise_error(ActiveRecord::StaleObjectError)
    end

    it "rejects a move to the current location" do
      expect { as_member(actor) { described_class.new(equipment:, location: matriz, actor:).call } }
        .to raise_error(EquipmentLifecycle::Relocate::SameLocation)
    end
  end

  describe EquipmentLifecycle::ChangeStatus do
    it "records status changes and ignores no-op changes" do
      as_member(actor) do
        described_class.new(equipment:, status: "inoperative", actor:, reason: "Compressor travado").call
        described_class.new(equipment:, status: "inoperative", actor:).call
      end

      in_tenant(organization) do
        expect(equipment.events.where(kind: "status_changed").sole).to have_attributes(from_status: "operational",
          to_status: "inoperative")
      end
    end
  end

  describe EquipmentLifecycle::Archive do
    it "archives and restores while keeping history" do
      as_member(actor) do
        described_class.new(equipment:, actor:).call
        described_class.new(equipment:, actor:, restore: true).call
      end

      in_tenant(organization) { expect(equipment.events.map(&:kind)).to eq(%w[restored archived registered]) }
    end
  end

  describe EquipmentLifecycle::Remove do
    it "deletes equipment registered by mistake" do
      as_member(actor) { described_class.new(equipment:).call }

      expect(in_tenant(organization) { Equipment.exists?(equipment.id) }).to be(false)
    end

    it "refuses to delete equipment with service history" do
      in_tenant(organization) { EquipmentLifecycle::History.record!(equipment, kind: "maintenance", actor:) }

      expect { as_member(actor) { described_class.new(equipment:).call } }.to raise_error(EquipmentLifecycle::Remove::InUse)
    end
  end
end
