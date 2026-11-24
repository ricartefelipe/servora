# frozen_string_literal: true

# Platform billing: one invoice per subscription period, charged through the
# platform's own payment account (never an organization's credentials).
# (subscription, period_start) is unique, so the daily billing run can repeat
# without duplicating invoices; every invoice has a stable external reference
# for provider lookups after lost responses.
class CreateSubscriptionInvoices < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    add_column :subscriptions, :current_period_end, :date

    create_tenant_table :subscription_invoices do |t|
      t.uuid :subscription_id, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.date :due_on, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.jsonb :lines, null: false, default: []
      t.string :status, null: false, default: "open"
      t.string :provider, null: false
      t.string :external_reference, null: false
      t.string :external_id
      t.string :charge_status, null: false, default: "pending"
      t.string :payment_url
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :paid_at
      t.datetime :last_synced_at
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_foreign_key :subscription_invoices, :subscriptions, column: :subscription_id
    add_index :subscription_invoices, %i[subscription_id period_start], unique: true
    add_index :subscription_invoices, %i[organization_id external_reference], unique: true
    add_index :subscription_invoices, %i[organization_id status due_on]
    add_inclusion_constraint :subscription_invoices, :status, %w[open paid void], name: "subscription_invoices_status"
    add_inclusion_constraint :subscription_invoices, :charge_status, %w[pending submitted unknown confirmed failed],
      name: "subscription_invoices_charge_status"
    add_check_constraint :subscription_invoices, "amount >= 0 AND period_end > period_start AND attempts >= 0",
      name: "subscription_invoices_values"
  end
end
