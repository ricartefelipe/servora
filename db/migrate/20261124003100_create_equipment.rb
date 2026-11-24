# frozen_string_literal: true

class CreateEquipment < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  STATUSES = %w[operational attention inoperative decommissioned].freeze

  def up
    create_tenant_table :equipment do |t|
      t.uuid :customer_id, null: false
      t.uuid :service_location_id, null: false
      t.string :equipment_type, null: false
      t.string :manufacturer
      t.string :model
      t.string :serial_number
      t.string :asset_tag
      t.string :capacity
      t.date :installed_on
      t.date :warranty_until
      t.string :warranty_notes
      t.string :operational_status, null: false, default: "operational"
      t.text :notes
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_foreign_key :equipment, :customers, column: :customer_id
    add_foreign_key :equipment, :service_locations,
      column: %i[organization_id customer_id service_location_id],
      primary_key: %i[organization_id customer_id id],
      name: "fk_equipment_location_of_same_customer"
    add_index :equipment, %i[organization_id customer_id]
    add_index :equipment, %i[organization_id service_location_id]
    add_index :equipment, %i[organization_id manufacturer serial_number], unique: true,
      where: "serial_number IS NOT NULL", name: "index_equipment_unique_serial"
    add_index :equipment, %i[organization_id asset_tag], unique: true, where: "asset_tag IS NOT NULL",
      name: "index_equipment_unique_asset_tag"
    add_inclusion_constraint :equipment, :operational_status, STATUSES, name: "equipment_operational_status"
    add_check_constraint :equipment, "warranty_until IS NULL OR installed_on IS NULL OR warranty_until >= installed_on",
      name: "equipment_warranty_after_installation"

    # Append-only history: relocations, ownership transfers and status changes.
    create_tenant_table :equipment_events, timestamps: :created_only do |t|
      t.string :kind, null: false
      t.uuid :from_customer_id
      t.uuid :to_customer_id
      t.uuid :from_location_id
      t.uuid :to_location_id
      t.string :from_status
      t.string :to_status
      t.string :description
      t.uuid :actor_membership_id
      t.datetime :occurred_at, null: false
    end
    add_tenant_reference :equipment_events, :equipment, column: :equipment_id, null: false, on_delete: :cascade
    add_index :equipment_events, %i[organization_id equipment_id occurred_at]
    add_inclusion_constraint :equipment_events, :kind,
      %w[registered relocated ownership_transferred status_changed archived restored maintenance], name: "equipment_events_kind"
  end

  def down
    drop_table :equipment_events
    drop_table :equipment
  end
end
