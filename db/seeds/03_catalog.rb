# frozen_string_literal: true

# Catalog of services and parts for the demonstration organizations.
module Seeds
  CATALOG = {
    "a" => [
      ["service", "Manutenção preventiva de split", "SRV-PREV-SPLIT", "un", "180.00", "65.0000", 60, false],
      ["service", "Higienização completa de evaporadora", "SRV-HIG-EVAP", "un", "240.00", "80.0000", 90, false],
      ["service", "Diagnóstico técnico", "SRV-DIAG", "un", "150.00", "55.0000", 45, false],
      ["service", "Hora técnica adicional", "SRV-HORA", "h", "120.00", "62.5000", 60, false],
      ["part", "Capacitor 35+5 µF", "PEC-CAP-355", "un", "89.90", "38.4000", nil, true],
      ["part", "Gás refrigerante R410A", "PEC-R410A", "kg", "95.00", "52.7500", nil, true],
      ["part", "Filtro secador 1/4\"", "PEC-FILTRO-14", "un", "42.00", "17.9000", nil, true]
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

Seeds.catalog("a")
Seeds.catalog("b")
puts "Catálogo de demonstração pronto."
