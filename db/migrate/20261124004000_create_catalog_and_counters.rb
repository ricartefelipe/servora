# frozen_string_literal: true

class CreateCatalogAndCounters < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  UNITS = %w[un h min m m2 m3 kg l par cj vb].freeze

  def change
    create_tenant_table :catalog_items do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.string :sku
      t.text :description
      t.string :unit, null: false, default: "un"
      # Money in BRL with 2 decimals; costs keep 4 decimals (moving average).
      t.decimal :unit_price, precision: 14, scale: 2, null: false, default: 0
      t.decimal :unit_cost, precision: 14, scale: 4
      t.integer :estimated_minutes
      t.boolean :tracks_inventory, null: false, default: false
      t.boolean :active, null: false, default: true
    end
    add_index :catalog_items, %i[organization_id sku], unique: true, where: "sku IS NOT NULL"
    add_index :catalog_items, %i[organization_id kind active name]
    add_inclusion_constraint :catalog_items, :kind, %w[service part], name: "catalog_items_kind"
    add_inclusion_constraint :catalog_items, :unit, UNITS, name: "catalog_items_unit"
    add_check_constraint :catalog_items, "unit_price >= 0 AND (unit_cost IS NULL OR unit_cost >= 0)", name: "catalog_items_money"
    add_check_constraint :catalog_items, "estimated_minutes IS NULL OR estimated_minutes BETWEEN 1 AND 10080",
      name: "catalog_items_estimated_minutes"
    add_check_constraint :catalog_items, "kind = 'part' OR NOT tracks_inventory", name: "catalog_items_inventory_only_parts"

    # Gap-tolerant sequential numbers per organization, scope and year,
    # allocated atomically with INSERT … ON CONFLICT DO UPDATE … RETURNING.
    create_tenant_table :organization_counters do |t|
      t.string :scope, null: false
      t.integer :year, null: false
      t.integer :value, null: false, default: 0
    end
    add_index :organization_counters, %i[organization_id scope year], unique: true, name: "index_organization_counters_key"
  end
end
