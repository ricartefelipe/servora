# frozen_string_literal: true

# Customers, service locations, contacts and equipment for the demonstration
# organizations. Idempotent: records are looked up by natural keys.
module Seeds
  CUSTOMERS = {
    "a" => [
      { kind: "company", name: "Supermercado Horizonte Ltda.", trade_name: "Horizonte Supermercados", document: "45997418000153",
        email: "manutencao@horizonte.test", phone: "1133334444",
        locations: [["Loja Paulista", "Av. Paulista", "1500", "São Paulo", "SP", "01310200"],
                    ["Centro de distribuição", "Rod. Anhanguera, km 98", nil, "Campinas", "SP", "13065900"]],
        contacts: [["Paula Reis", "paula@horizonte.test", "Gerente de facilities", true]],
        equipment: [["Câmara fria", "Frigotech", "CF-900", "CF900-2231", "Centro de distribuição", "operational"],
                    ["Split hi-wall", "Climatec", "CT-24", "CT24-88120", "Loja Paulista", "attention"],
                    ["Cassete", "Climatec", "CS-48", "CS48-77001", "Loja Paulista", "operational"]] },
      { kind: "individual", name: "Renato Albuquerque", document: "52998224725", email: "renato@cliente.test",
        locations: [["Residência", "Rua das Acácias", "45", "São Paulo", "SP", "04567010"]],
        contacts: [["Renato Albuquerque", "renato@cliente.test", "Proprietário", true]],
        equipment: [["Split piso-teto", "Ventura", "VT-36", "VT36-0091", "Residência", "inoperative"]] }
    ],
    "b" => [
      { kind: "company", name: "Condomínio Edifício Aurora", document: "11222333000181", email: "sindico@aurora.test",
        locations: [["Torre A", "Rua Voluntários da Pátria", "800", "Porto Alegre", "RS", "90230010"]],
        contacts: [["Lúcia Andrade", "sindico@aurora.test", "Síndica", true]],
        equipment: [["Elevador", "Ascend", "AS-10", "AS10-5512", "Torre A", "operational"]] }
    ]
  }.freeze

  def self.customers(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      CUSTOMERS.fetch(key).each { |data| seed_customer(organization, data) }
    end
  end

  def self.seed_customer(organization, data)
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
    data[:equipment].each { |attributes| seed_equipment(organization, customer, locations, attributes) }
  end

  def self.seed_equipment(organization, customer, locations, attributes)
    type, manufacturer, model, serial, location_name, status = attributes
    return if organization.equipment.exists?(serial_number: serial)

    EquipmentLifecycle::Register.new(organization:, actor: nil, attributes: {
      customer_id: customer.id, service_location_id: locations.fetch(location_name).id, equipment_type: type,
      manufacturer:, model:, serial_number: serial, operational_status: status,
      installed_on: Date.new(2024, 3, 15), warranty_until: Date.new(2027, 3, 15)
    }).call
  end
end

Seeds.customers("a")
Seeds.customers("b")
puts "Clientes e equipamentos de demonstração prontos."
