# frozen_string_literal: true

# Customers, service locations, contacts and equipment for the demonstration
# organizations (Seeds::CUSTOMERS, support/customers.rb). Idempotent: records
# are looked up by natural keys.
#
# Installation and warranty dates are relative to the run date, so the
# warranties keep their spread (one has already expired). With the
# demonstration activity the equipment starts operational and the story
# changes its state through its work orders.
require_relative "support/story_clock"
require_relative "support/customers"

module Seeds
  def self.customers(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      CUSTOMERS.fetch(key).each { |data| seed_customer(organization, data) }
    end
  end

  def self.seed_customer(organization, data, today: StoryClock.today)
    customer = organization.customers.find_or_create_by!(document: data[:document]) do |record|
      record.assign_attributes(data.slice(:kind, :name, :trade_name, :email, :phone))
    end
    locations = data[:locations].to_h do |location_data|
      name, street, number, city, state, postal_code = location_data
      [name, customer.service_locations.find_or_create_by!(name:) do |location|
        location.assign_attributes(organization:, street:, number:, city:, state:, postal_code:)
      end]
    end
    data[:contacts].each do |name, email, position, can_approve|
      customer.contacts.find_or_create_by!(email:) do |contact|
        contact.assign_attributes(organization:, name:, position:, can_approve:, portal_enabled: true)
      end
    end
    data[:equipment].each { |attributes| seed_equipment(organization, customer, locations, attributes, today) }
  end

  def self.seed_equipment(organization, customer, locations, attributes, today)
    type, manufacturer, model, serial, location_name, status, installed_ago, warranty_months = attributes
    return if organization.equipment.exists?(serial_number: serial)

    installed_on = today << installed_ago
    EquipmentLifecycle::Register.new(organization:, actor: nil, attributes: {
      customer_id: customer.id, service_location_id: locations.fetch(location_name).id, equipment_type: type,
      manufacturer:, model:, serial_number: serial, operational_status: StoryClock.enabled? ? "operational" : status,
      installed_on:, warranty_until: installed_on >> warranty_months
    }).call
  end
end

Seeds::StoryClock.at_origin do
  Seeds.customers("a")
  Seeds.customers("b")
end
puts "Clientes e equipamentos de demonstração prontos."
