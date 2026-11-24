# frozen_string_literal: true

# Platform subscription of each organization (the SaaS plan), independent from
# the maintenance contracts organizations sign with their own customers.
#
# plans and plan_modules are platform reference data, loaded by
# Servora::ReferenceData (owner role, idempotent) and read-only for the
# application role (DatabasePrivileges).
class CreatePlatformSubscriptions < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    create_table :plans, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :name, null: false
      t.decimal :monthly_price, precision: 14, scale: 2, null: false
      t.integer :included_technicians, null: false
      t.decimal :extra_technician_price, precision: 14, scale: 2, null: false
      t.decimal :implementation_fee, precision: 14, scale: 2, null: false
      t.string :modules, array: true, null: false, default: []
      t.integer :trial_days, null: false, default: 14
      t.integer :position, null: false
      t.timestamps
    end
    add_check_constraint :plans, "monthly_price >= 0 AND extra_technician_price >= 0 AND implementation_fee >= 0 " \
                                 "AND included_technicians > 0 AND trial_days >= 0", name: "plans_values"

    create_table :plan_modules, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :name, null: false
      t.decimal :monthly_price, precision: 14, scale: 2, null: false
      t.integer :position, null: false
      t.timestamps
    end
    add_check_constraint :plan_modules, "monthly_price >= 0", name: "plan_modules_price"

    create_tenant_table :subscriptions do |t|
      t.string :status, null: false, default: "trialing"
      t.date :trial_ends_on
      t.integer :technician_seats, null: false
      t.string :addon_modules, array: true, null: false, default: []
      t.decimal :monthly_amount, precision: 14, scale: 2, null: false
      t.decimal :implementation_fee, precision: 14, scale: 2, null: false, default: 0
      t.string :implementation_status, null: false, default: "not_applicable"
      t.datetime :activated_at
      t.datetime :canceled_at
      t.integer :lock_version, null: false, default: 0
      t.uuid :plan_id, null: false
    end
    add_foreign_key :subscriptions, :plans
    add_index :subscriptions, :organization_id, unique: true, name: "index_subscriptions_one_per_organization"
    add_inclusion_constraint :subscriptions, :status, %w[trialing active past_due canceled], name: "subscriptions_status"
    add_inclusion_constraint :subscriptions, :implementation_status, %w[not_applicable pending paid waived],
      name: "subscriptions_implementation_status"
    add_check_constraint :subscriptions, "technician_seats > 0 AND monthly_amount >= 0 AND implementation_fee >= 0 " \
                                         "AND (status <> 'trialing' OR trial_ends_on IS NOT NULL)",
      name: "subscriptions_values"
  end

  def down
    drop_table :subscriptions
    drop_table :plan_modules
    drop_table :plans
  end
end
