# frozen_string_literal: true

# Warehouses and initial stock. Receipts use deterministic idempotency keys,
# so running the seed again never duplicates stock. With the demonstration
# activity the opening receipts are dated at the origin of the story, before
# every movement it records; the story then buys back each week what the
# routine work consumed (DemoActivity::History), so the balances stay close to
# these levels.
require_relative "support/story_clock"

module Seeds
  WAREHOUSES = {
    "a" => [["Almoxarifado central", "central", nil], ["Van 01 — Diego", "vehicle", "diego@clima-norte.test"]],
    "b" => [["Depósito Predial Sul", "central", nil]]
  }.freeze

  # [warehouse, sku, quantity, unit cost, minimum]
  INITIAL_STOCK = {
    "a" => [
      ["Almoxarifado central", "PEC-CAP-355", "12", "38.4000", "5"],
      ["Almoxarifado central", "PEC-R410A", "25.5", "52.7500", "10"],
      ["Almoxarifado central", "PEC-FILTRO-14", "3", "17.9000", "4"],
      ["Almoxarifado central", "PEC-RELE-220", "2", "64.2000", "2"],
      ["Almoxarifado central", "PEC-CONTATOR-32", "5", "71.5000", "2"],
      ["Almoxarifado central", "PEC-DISJ-20", "10", "26.8000", "4"],
      ["Almoxarifado central", "PEC-MOTOR-VENT", "3", "182.0000", "1"],
      ["Almoxarifado central", "PEC-BOMBA-DRENO", "3", "141.0000", "1"],
      ["Almoxarifado central", "PEC-ISOL-38", "60", "5.9000", "20"],
      ["Almoxarifado central", "PEC-R32", "9", "64.3000", "4"],
      ["Almoxarifado central", "PEC-SENSOR-NTC", "6", "19.8000", "2"],
      ["Van 01 — Diego", "PEC-CAP-355", "2", "38.4000", "1"]
    ],
    "b" => [["Depósito Predial Sul", "PEC-CABO-8", "120", "21.0000", "30"]]
  }.freeze

  def self.inventory(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      warehouses = WAREHOUSES.fetch(key).to_h { |row| [row.first, seed_warehouse(organization, *row)] }
      INITIAL_STOCK.fetch(key).each { |row| seed_stock(organization, warehouses, row) }
    end
  end

  def self.seed_warehouse(organization, name, kind, custodian_email)
    custodian = custodian_email && organization.memberships.joins(:user).find_by!(users: { email: custodian_email })
    organization.warehouses.find_or_create_by!(name:) do |warehouse|
      warehouse.assign_attributes(kind:, custodian_membership_id: custodian&.id)
    end
  end

  def self.seed_stock(organization, warehouses, row)
    warehouse_name, sku, quantity, unit_cost, minimum = row
    warehouse = warehouses.fetch(warehouse_name)
    item = organization.catalog_items.find_by!(sku:)
    key = Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, "servora-seed:#{organization.id}:#{warehouse.id}:#{sku}")
    Inventory::Receive.new(warehouse:, item:, quantity:, unit_cost:, actor: nil, reason: "Carga inicial de demonstração",
      idempotency_key: key).call
    Inventory::SetMinimum.new(warehouse:, item:, minimum:, actor: nil).call
  end
end

Seeds::StoryClock.at_origin do
  Seeds.inventory("a")
  Seeds.inventory("b")
end
puts "Depósitos e saldos iniciais prontos."
