# frozen_string_literal: true

class CreateCustomersAndLocations < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    enable_extension "pg_trgm"

    create_tenant_table :customers do |t|
      t.string :kind, null: false
      t.string :name, null: false
      t.string :trade_name
      t.string :document
      t.string :email
      t.string :phone
      t.text :notes
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0
    end
    add_inclusion_constraint :customers, :kind, %w[individual company], name: "customers_kind"
    add_index :customers, %i[organization_id document], unique: true, where: "document IS NOT NULL",
      name: "index_customers_unique_document"
    add_index :customers, :name, using: :gin, opclass: :gin_trgm_ops, name: "index_customers_name_trgm"
    add_index :customers, %i[organization_id archived_at name]

    create_tenant_table :service_locations do |t|
      t.string :name, null: false
      t.string :street, null: false
      t.string :number
      t.string :complement
      t.string :district
      t.string :city, null: false
      t.string :state, null: false, limit: 2
      t.string :postal_code
      t.text :access_instructions
      t.datetime :archived_at
    end
    add_tenant_reference :service_locations, :customers, null: false
    # Equipment references (organization_id, customer_id, id) so a piece of
    # equipment can only be installed at a location of its own customer.
    add_index :service_locations, %i[organization_id customer_id id], unique: true,
      name: "index_service_locations_on_customer_key"
    add_check_constraint :service_locations, "state ~ '^[A-Z]{2}$'", name: "service_locations_state"
    add_check_constraint :service_locations, "postal_code IS NULL OR postal_code ~ '^[0-9]{8}$'",
      name: "service_locations_postal_code"

    create_tenant_table :customer_contacts do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :position
      t.boolean :can_approve, null: false, default: false
      t.boolean :can_follow, null: false, default: true
      t.boolean :portal_enabled, null: false, default: false
      t.datetime :archived_at
    end
    add_tenant_reference :customer_contacts, :customers, null: false
    add_check_constraint :customer_contacts, "NOT portal_enabled OR email IS NOT NULL",
      name: "customer_contacts_portal_requires_email"
  end

  def down
    drop_table :customer_contacts
    drop_table :service_locations
    drop_table :customers
    disable_extension "pg_trgm"
  end
end
