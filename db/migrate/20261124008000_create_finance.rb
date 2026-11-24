# frozen_string_literal: true

# Operational finance: receivables per work order, payments, refunds,
# discounts, gateway charges, expenses and the append-only financial history.
#
# Money is numeric(14,2) everywhere. Check constraints keep the receivable
# position consistent no matter which code path writes it:
#   0 ≤ refunded ≤ paid, discount ≤ amount, paid − refunded ≤ amount − discount,
#   canceled receivables hold no net payment, paid ones have no balance left.
class CreateFinance < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  PAYMENT_METHODS = %w[pix boleto transfer cash card_gateway other].freeze
  CHARGE_STATUSES = %w[pending submitted unknown confirmed failed canceled].freeze
  EVENT_KINDS = %w[issued payment discount refund canceled charge_requested charge_submitted charge_confirmed
                   charge_failed charge_unknown charge_canceled].freeze

  def change
    # The receivable's customer must be the work order's customer.
    add_index :work_orders, %i[organization_id id customer_id], unique: true, name: "index_work_orders_on_customer_key"

    create_receivables
    create_payment_charges
    create_payments
    create_financial_events
    create_expenses
    create_payment_integrations
  end

  private

  def create_receivables
    create_tenant_table :receivables do |t|
      t.string :number, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.decimal :discount_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :paid_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :refunded_amount, precision: 14, scale: 2, null: false, default: 0
      t.string :status, null: false, default: "open"
      t.date :due_on, null: false
      t.datetime :settled_at
      t.datetime :canceled_at
      t.text :cancel_reason
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :receivables, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :receivables, :customers, column: :customer_id, null: false
    add_tenant_reference :receivables, :memberships, column: :created_by_membership_id, index: false
    add_foreign_key :receivables, :work_orders, column: %i[organization_id work_order_id customer_id],
      primary_key: %i[organization_id id customer_id], name: "fk_receivables_work_order_customer"
    add_index :receivables, %i[organization_id number], unique: true
    add_index :receivables, %i[organization_id status due_on]
    add_inclusion_constraint :receivables, :status, %w[open partially_paid paid canceled], name: "receivables_status"
    add_check_constraint :receivables,
      "amount > 0 AND discount_amount >= 0 AND paid_amount >= 0 AND refunded_amount >= 0 " \
      "AND refunded_amount <= paid_amount AND discount_amount <= amount " \
      "AND paid_amount - refunded_amount <= amount - discount_amount",
      name: "receivables_values"
    add_check_constraint :receivables,
      "(status = 'canceled') = (canceled_at IS NOT NULL) " \
      "AND (status <> 'canceled' OR paid_amount = refunded_amount) " \
      "AND (status <> 'paid' OR paid_amount - refunded_amount = amount - discount_amount)",
      name: "receivables_status_consistency"
  end

  def create_payment_charges
    create_tenant_table :payment_charges do |t|
      t.string :provider, null: false
      t.string :external_reference, null: false
      t.string :external_id
      t.string :status, null: false, default: "pending"
      t.string :billing_type, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.date :due_on, null: false
      t.string :payment_url
      t.text :last_error
      t.integer :attempts, null: false, default: 0
      t.datetime :submitted_at
      t.datetime :confirmed_at
      t.datetime :last_synced_at
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :payment_charges, :receivables, column: :receivable_id, null: false
    add_index :payment_charges, %i[organization_id external_reference], unique: true
    add_index :payment_charges, %i[organization_id provider external_id], unique: true, where: "external_id IS NOT NULL",
      name: "index_payment_charges_external_id"
    # At most one charge in flight per receivable.
    add_index :payment_charges, :receivable_id, unique: true,
      where: "(status)::text = ANY (ARRAY['pending'::text, 'submitted'::text, 'unknown'::text])",
      name: "index_payment_charges_single_active"
    add_index :payment_charges, %i[status last_synced_at]
    add_inclusion_constraint :payment_charges, :status, CHARGE_STATUSES, name: "payment_charges_status"
    add_inclusion_constraint :payment_charges, :provider, %w[simulator asaas], name: "payment_charges_provider"
    add_inclusion_constraint :payment_charges, :billing_type, %w[pix boleto], name: "payment_charges_billing_type"
    add_check_constraint :payment_charges, "amount > 0 AND attempts >= 0", name: "payment_charges_values"
  end

  def create_payments
    create_tenant_table :payments do |t|
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.decimal :refunded_amount, precision: 14, scale: 2, null: false, default: 0
      t.string :payment_method, null: false
      t.datetime :paid_at, null: false
      t.string :idempotency_key
      t.text :notes
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :payments, :receivables, column: :receivable_id, null: false
    add_tenant_reference :payments, :payment_charges, column: :payment_charge_id
    add_tenant_reference :payments, :memberships, column: :recorded_by_membership_id, index: false
    add_index :payments, %i[organization_id idempotency_key], unique: true, where: "idempotency_key IS NOT NULL",
      name: "index_payments_idempotency"
    add_inclusion_constraint :payments, :payment_method, PAYMENT_METHODS, name: "payments_method"
    add_check_constraint :payments, "amount > 0 AND refunded_amount >= 0 AND refunded_amount <= amount", name: "payments_values"
  end

  def create_financial_events
    create_tenant_table :financial_events, timestamps: :created_only do |t|
      t.string :kind, null: false
      t.decimal :amount, precision: 14, scale: 2
      t.jsonb :details, null: false, default: {}
      t.uuid :actor_membership_id
      t.string :actor_label
      t.datetime :occurred_at, null: false
    end
    add_tenant_reference :financial_events, :receivables, column: :receivable_id, null: false
    add_tenant_reference :financial_events, :payments, column: :payment_id, index: false
    add_inclusion_constraint :financial_events, :kind, EVENT_KINDS, name: "financial_events_kind"
  end

  def create_expenses
    create_tenant_table :expenses do |t|
      t.string :category, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.date :incurred_on, null: false
    end
    add_tenant_reference :expenses, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :expenses, :memberships, column: :recorded_by_membership_id, index: false
    add_inclusion_constraint :expenses, :category, %w[travel toll parking meals outsourced materials other],
      name: "expenses_category"
    add_check_constraint :expenses, "amount > 0", name: "expenses_amount"
  end

  def create_payment_integrations
    create_tenant_table :payment_integrations do |t|
      t.string :provider, null: false, default: "simulator"
      t.text :api_key
      t.string :default_billing_type, null: false, default: "pix"
    end
    add_index :payment_integrations, :organization_id, unique: true, name: "index_payment_integrations_single"
    add_inclusion_constraint :payment_integrations, :provider, %w[simulator asaas], name: "payment_integrations_provider"
    add_inclusion_constraint :payment_integrations, :default_billing_type, %w[pix boleto],
      name: "payment_integrations_billing_type"
    add_check_constraint :payment_integrations, "provider = 'simulator' OR api_key IS NOT NULL",
      name: "payment_integrations_credentials"
  end
end
