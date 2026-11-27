# frozen_string_literal: true

# Catalog of services and parts for the demonstration organizations.
require_relative "support/story_clock"

module Seeds
  CATALOG = {
    "a" => [
      ["service", "Manutenção preventiva de split", "SRV-PREV-SPLIT", "un", "180.00", "65.0000", 60, false],
      ["service", "Higienização completa de evaporadora", "SRV-HIG-EVAP", "un", "240.00", "80.0000", 90, false],
      ["service", "Diagnóstico técnico", "SRV-DIAG", "un", "150.00", "55.0000", 45, false],
      ["service", "Hora técnica adicional", "SRV-HORA", "h", "120.00", "62.5000", 60, false],
      ["service", "Instalação de split hi-wall (até 18.000 BTU/h)", "SRV-INST-SPLIT", "un", "680.00", "290.0000", 240, false],
      ["part", "Capacitor 35+5 µF", "PEC-CAP-355", "un", "89.90", "38.4000", nil, true],
      ["part", "Gás refrigerante R410A", "PEC-R410A", "kg", "95.00", "52.7500", nil, true],
      ["part", "Filtro secador 1/4\"", "PEC-FILTRO-14", "un", "42.00", "17.9000", nil, true],
      ["part", "Relé de partida 220 V", "PEC-RELE-220", "un", "148.00", "64.2000", nil, true],
      ["part", "Contator tripolar 32 A 220 V", "PEC-CONTATOR-32", "un", "168.00", "71.5000", nil, true],
      ["part", "Disjuntor bipolar 20 A curva C", "PEC-DISJ-20", "un", "64.00", "26.8000", nil, true],
      ["part", "Motor ventilador da condensadora 1/6 cv", "PEC-MOTOR-VENT", "un", "389.00", "182.0000", nil, true],
      ["part", "Bomba de dreno para cassete", "PEC-BOMBA-DRENO", "un", "312.00", "141.0000", nil, true],
      ["part", "Isolamento térmico elastomérico 3/8\"", "PEC-ISOL-38", "m", "14.50", "5.9000", nil, true],
      ["part", "Gás refrigerante R32", "PEC-R32", "kg", "118.00", "64.3000", nil, true],
      ["part", "Sensor de temperatura NTC 10 kΩ", "PEC-SENSOR-NTC", "un", "54.00", "19.8000", nil, true]
    ],
    "b" => [
      ["service", "Inspeção mensal de elevador", "SRV-ELEV-INSP", "un", "650.00", "240.0000", 120, false],
      ["part", "Cabo de tração 8 mm", "PEC-CABO-8", "m", "38.00", "21.0000", nil, true]
    ]
  }.freeze

  def self.catalog(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      CATALOG.fetch(key).each { |row| seed_catalog_item(organization, row) }
    end
  end

  def self.seed_catalog_item(organization, row)
    kind, name, sku, unit, price, cost, minutes, inventory = row
    organization.catalog_items.find_or_create_by!(sku:) do |item|
      item.assign_attributes(kind:, name:, unit:, unit_price: BigDecimal(price), unit_cost: BigDecimal(cost),
        estimated_minutes: minutes, tracks_inventory: inventory)
    end
  end
end

Seeds::StoryClock.at_origin do
  Seeds.catalog("a")
  Seeds.catalog("b")
end
puts "Catálogo de demonstração pronto."
