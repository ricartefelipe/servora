# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer and equipment integrity in PostgreSQL" do
  def in_savepoint(&) = ActiveRecord::Base.transaction(requires_new: true, &)

  it "refuses equipment installed at a location of another customer, even bypassing validations" do
    location = create(:service_location)
    other_customer = create(:customer, organization: location.organization)
    equipment = build(:equipment, location:, customer: other_customer)

    in_tenant(location.organization) do
      expect { in_savepoint { equipment.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "refuses references to a location of another organization" do
    location = create(:service_location)
    foreign_customer = create(:customer)

    in_tenant(foreign_customer.organization) do
      equipment = Equipment.new(organization: foreign_customer.organization, customer: foreign_customer,
        service_location_id: location.id, equipment_type: "Split")
      expect { in_savepoint { equipment.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "keeps equipment history append-only for the application role" do
    equipment = create(:equipment)
    event = in_tenant(equipment.organization) do
      EquipmentLifecycle::History.record!(equipment, kind: "registered", actor: nil)
    end

    in_tenant(equipment.organization) do
      expect { in_savepoint { EquipmentEvent.where(id: event.id).update_all(kind: "archived") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end
end
