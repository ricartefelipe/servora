# frozen_string_literal: true

class CreateWorkOrders < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  STATUSES = %w[open awaiting_approval approved scheduled in_progress waiting_parts waiting_customer completed reopened
                canceled].freeze
  ORIGINS = %w[phone email whatsapp portal quote preventive internal].freeze
  PRIORITIES = %w[low normal high urgent].freeze

  def up
    # Equipment of a work order must belong to the work order's customer.
    add_index :equipment, %i[organization_id customer_id id], unique: true, name: "index_equipment_on_customer_key"

    create_tenant_table :work_orders do |t|
      t.string :number, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "open"
      t.string :origin, null: false
      t.string :priority, null: false, default: "normal"
      t.uuid :customer_id, null: false
      t.uuid :service_location_id, null: false
      t.text :problem_description, null: false
      t.text :diagnosis
      t.text :solution
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :canceled_at
      t.text :cancel_reason
      t.integer :reopened_count, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_foreign_key :work_orders, :customers, column: :customer_id
    add_foreign_key :work_orders, :service_locations, column: %i[organization_id customer_id service_location_id],
      primary_key: %i[organization_id customer_id id], name: "fk_work_orders_location_of_customer"
    add_tenant_reference :work_orders, :quote_versions, column: :quote_version_id, index: false
    add_tenant_reference :work_orders, :service_types, column: :service_type_id, index: false
    add_tenant_reference :work_orders, :memberships, column: :created_by_membership_id, null: false, index: false
    add_index :work_orders, %i[organization_id number], unique: true
    # Idempotent conversion: one work order per approved quote version.
    add_index :work_orders, %i[organization_id quote_version_id], unique: true, where: "quote_version_id IS NOT NULL",
      name: "index_work_orders_one_per_quote_version"
    add_index :work_orders, %i[organization_id status priority requested_at]
    add_index :work_orders, %i[organization_id customer_id]
    add_inclusion_constraint :work_orders, :status, STATUSES, name: "work_orders_status"
    add_inclusion_constraint :work_orders, :origin, ORIGINS, name: "work_orders_origin"
    add_inclusion_constraint :work_orders, :priority, PRIORITIES, name: "work_orders_priority"
    add_check_constraint :work_orders, "status <> 'completed' OR completed_at IS NOT NULL", name: "work_orders_completed_at"
    add_check_constraint :work_orders, "status <> 'canceled' OR (canceled_at IS NOT NULL AND cancel_reason IS NOT NULL)",
      name: "work_orders_cancel_reason"

    create_tenant_table :work_order_equipment do |t|
      t.uuid :customer_id, null: false
      t.uuid :equipment_id, null: false
    end
    add_tenant_reference :work_order_equipment, :work_orders, column: :work_order_id, null: false, on_delete: :cascade
    add_foreign_key :work_order_equipment, :equipment, column: %i[organization_id customer_id equipment_id],
      primary_key: %i[organization_id customer_id id], name: "fk_work_order_equipment_of_customer"
    add_index :work_order_equipment, %i[organization_id work_order_id equipment_id], unique: true,
      name: "index_work_order_equipment_unique"
    add_index :work_order_equipment, %i[organization_id equipment_id]

    create_tenant_table :work_order_assignments do |t|
      t.string :role, null: false, default: "technician"
    end
    add_tenant_reference :work_order_assignments, :work_orders, column: :work_order_id, null: false, on_delete: :cascade,
      index: false
    add_tenant_reference :work_order_assignments, :memberships, column: :membership_id, null: false
    add_index :work_order_assignments, %i[organization_id work_order_id membership_id], unique: true,
      name: "index_assignments_unique"
    add_inclusion_constraint :work_order_assignments, :role, %w[lead technician], name: "work_order_assignments_role"

    create_tenant_table :work_order_items do |t|
      t.string :kind, null: false
      t.string :source, null: false
      t.string :description, null: false
      t.string :unit, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :unit_price, precision: 14, scale: 2, null: false
      t.decimal :unit_cost, precision: 14, scale: 4
      t.decimal :discount_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :line_total, precision: 14, scale: 2, null: false
      t.string :authorization_status, null: false
      t.datetime :authorized_at
      t.string :authorization_channel
      t.text :authorization_note
      t.uuid :authorized_by_contact_id
      t.uuid :authorized_by_membership_id
    end
    add_tenant_reference :work_order_items, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :work_order_items, :catalog_items, column: :catalog_item_id, index: false
    add_tenant_foreign_key :work_order_items, :customer_contacts, column: :authorized_by_contact_id
    add_tenant_foreign_key :work_order_items, :memberships, column: :authorized_by_membership_id
    add_inclusion_constraint :work_order_items, :kind, %w[service part other], name: "work_order_items_kind"
    add_inclusion_constraint :work_order_items, :source, %w[quote additional preventive manual], name: "work_order_items_source"
    add_inclusion_constraint :work_order_items, :authorization_status, %w[authorized pending rejected],
      name: "work_order_items_authorization_status"
    add_check_constraint :work_order_items, "quantity > 0 AND unit_price >= 0 AND discount_amount >= 0",
      name: "work_order_items_values"
    add_check_constraint :work_order_items,
      "line_total = round(quantity * unit_price, 2) - discount_amount AND line_total >= 0", name: "work_order_items_line_total"
    add_check_constraint :work_order_items,
      "authorization_status = 'pending' OR (authorized_at IS NOT NULL AND authorized_by_membership_id IS NOT NULL)",
      name: "work_order_items_authorization_evidence"

    create_tenant_table :work_order_checklist_items do |t|
      t.string :label, null: false
      t.string :response_kind, null: false
      t.boolean :required, null: false
      t.integer :position, null: false
      t.string :response
      t.datetime :responded_at
      t.uuid :responded_by_membership_id
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :work_order_checklist_items, :work_orders, column: :work_order_id, null: false, on_delete: :cascade
    add_tenant_foreign_key :work_order_checklist_items, :memberships, column: :responded_by_membership_id
    add_inclusion_constraint :work_order_checklist_items, :response_kind, %w[check text number], name: "work_order_checklist_kind"

    create_tenant_table :work_order_transitions, timestamps: :created_only do |t|
      t.string :from_status
      t.string :to_status, null: false
      t.text :reason
      t.string :actor_label
      t.uuid :actor_membership_id
    end
    add_tenant_reference :work_order_transitions, :work_orders, column: :work_order_id, null: false

    # Completion reports are kept per completion: reopening never erases them.
    create_tenant_table :work_order_reports, timestamps: :created_only do |t|
      t.integer :version_number, null: false
      t.jsonb :data, null: false
      t.string :content_digest, null: false
      t.uuid :generated_by_membership_id
    end
    add_tenant_reference :work_order_reports, :work_orders, column: :work_order_id, null: false, index: false
    add_index :work_order_reports, %i[organization_id work_order_id version_number], unique: true,
      name: "index_work_order_reports_version"
  end

  def down
    drop_table :work_order_reports
    drop_table :work_order_transitions
    drop_table :work_order_checklist_items
    drop_table :work_order_items
    drop_table :work_order_assignments
    drop_table :work_order_equipment
    drop_table :work_orders
    remove_index :equipment, name: "index_equipment_on_customer_key"
  end
end
