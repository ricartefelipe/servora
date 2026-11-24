# frozen_string_literal: true

# Maintenance contracts (versioned terms) and preventive plans.
#
# * contract_versions is append-only: every change of commercial terms keeps
#   the previous snapshot;
# * work orders, plans and plan equipment reference the contract together with
#   the customer (composite keys), so a contract can never serve another
#   customer's work order or equipment;
# * maintenance_occurrences has a stable identity (plan, sequence): a missed
#   scheduler run, a retry or two concurrent generators can never create the
#   same occurrence twice.
class CreateContractsAndPreventive < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_contracts
    create_plans
    create_occurrences
  end

  private

  def create_contracts
    create_tenant_table :contracts do |t|
      t.string :number, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.date :starts_on, null: false
      t.date :ends_on
      t.decimal :monthly_fee, precision: 14, scale: 2, null: false, default: 0
      t.integer :monthly_visit_limit
      t.boolean :covers_parts, null: false, default: false
      t.text :scope
      t.integer :current_version, null: false, default: 1
      t.datetime :activated_at
      t.datetime :suspended_at
      t.datetime :ended_at
      t.text :status_reason
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :contracts, :customers, column: :customer_id, null: false
    add_tenant_reference :contracts, :memberships, column: :created_by_membership_id, index: false
    add_index :contracts, %i[organization_id number], unique: true
    add_index :contracts, %i[organization_id customer_id id], unique: true, name: "index_contracts_on_customer_key"
    add_inclusion_constraint :contracts, :status, %w[draft active suspended ended], name: "contracts_status"
    add_check_constraint :contracts,
      "(ends_on IS NULL OR ends_on >= starts_on) AND monthly_fee >= 0 " \
      "AND (monthly_visit_limit IS NULL OR monthly_visit_limit > 0) AND current_version > 0",
      name: "contracts_values"
    add_check_constraint :contracts,
      "((status)::text <> 'active'::text OR activated_at IS NOT NULL) " \
      "AND ((status)::text <> 'suspended'::text OR suspended_at IS NOT NULL) " \
      "AND ((status)::text <> 'ended'::text OR ended_at IS NOT NULL)",
      name: "contracts_status_timestamps"

    create_tenant_table :contract_versions, timestamps: :created_only do |t|
      t.integer :version_number, null: false
      t.jsonb :terms, null: false
      t.text :reason
      t.uuid :created_by_membership_id
    end
    add_tenant_reference :contract_versions, :contracts, column: :contract_id, null: false, index: false
    add_index :contract_versions, %i[contract_id version_number], unique: true

    create_tenant_table :contract_service_types, timestamps: :created_only
    add_tenant_reference :contract_service_types, :contracts, column: :contract_id, null: false, index: false
    add_tenant_reference :contract_service_types, :service_types, column: :service_type_id, null: false
    add_index :contract_service_types, %i[contract_id service_type_id], unique: true

    add_column :work_orders, :contract_id, :uuid
    add_index :work_orders, %i[organization_id contract_id requested_at], name: "index_work_orders_on_contract_usage"
    add_foreign_key :work_orders, :contracts, column: %i[organization_id customer_id contract_id],
      primary_key: %i[organization_id customer_id id], name: "fk_work_orders_contract_customer"
  end

  def create_plans
    create_tenant_table :maintenance_plans do |t|
      t.string :title, null: false
      t.string :priority, null: false, default: "normal"
      t.string :frequency_unit, null: false
      t.integer :frequency_interval, null: false, default: 1
      t.string :schedule_mode, null: false, default: "calendar"
      t.date :anchor_date, null: false
      t.integer :anchor_sequence, null: false, default: 1
      t.integer :last_sequence, null: false, default: 0
      t.integer :lead_days, null: false, default: 7
      t.boolean :active, null: false, default: true
      t.text :instructions
      t.integer :lock_version, null: false, default: 0
      t.uuid :customer_id, null: false
      t.uuid :service_location_id, null: false
    end
    add_tenant_reference :maintenance_plans, :contracts, column: :contract_id, null: false
    add_tenant_reference :maintenance_plans, :service_types, column: :service_type_id
    add_tenant_reference :maintenance_plans, :memberships, column: :created_by_membership_id, index: false
    add_foreign_key :maintenance_plans, :contracts, column: %i[organization_id customer_id contract_id],
      primary_key: %i[organization_id customer_id id], name: "fk_maintenance_plans_contract_customer"
    add_foreign_key :maintenance_plans, :service_locations, column: %i[organization_id customer_id service_location_id],
      primary_key: %i[organization_id customer_id id], name: "fk_maintenance_plans_location_customer"
    add_inclusion_constraint :maintenance_plans, :frequency_unit, %w[week month year], name: "maintenance_plans_unit"
    add_inclusion_constraint :maintenance_plans, :schedule_mode, %w[calendar after_completion], name: "maintenance_plans_mode"
    add_inclusion_constraint :maintenance_plans, :priority, %w[low normal high urgent], name: "maintenance_plans_priority"
    add_check_constraint :maintenance_plans,
      "frequency_interval >= 1 AND frequency_interval <= 104 AND lead_days >= 0 AND lead_days <= 90 " \
      "AND anchor_sequence >= 1 " \
      "AND last_sequence >= 0 AND anchor_sequence <= last_sequence + 1",
      name: "maintenance_plans_values"

    create_tenant_table :maintenance_plan_equipment, timestamps: :created_only do |t|
      t.uuid :customer_id, null: false
      t.uuid :equipment_id, null: false
    end
    add_tenant_reference :maintenance_plan_equipment, :maintenance_plans, column: :maintenance_plan_id, null: false,
      index: false
    add_foreign_key :maintenance_plan_equipment, :equipment, column: %i[organization_id customer_id equipment_id],
      primary_key: %i[organization_id customer_id id], name: "fk_maintenance_plan_equipment_customer"
    add_index :maintenance_plan_equipment, %i[maintenance_plan_id equipment_id], unique: true,
      name: "index_maintenance_plan_equipment_unique"
  end

  def create_occurrences
    create_tenant_table :maintenance_occurrences do |t|
      t.integer :sequence, null: false
      t.date :due_on, null: false
      t.datetime :generated_at, null: false
    end
    add_tenant_reference :maintenance_occurrences, :maintenance_plans, column: :maintenance_plan_id, null: false,
      index: false
    add_tenant_reference :maintenance_occurrences, :work_orders, column: :work_order_id, null: false, index: false
    add_index :maintenance_occurrences, %i[maintenance_plan_id sequence], unique: true,
      name: "index_maintenance_occurrences_identity"
    add_index :maintenance_occurrences, :work_order_id, unique: true
    add_check_constraint :maintenance_occurrences, "sequence >= 1", name: "maintenance_occurrences_sequence"
  end
end
