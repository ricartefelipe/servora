# frozen_string_literal: true

# Service invoices (NFS-e) issued through the payment provider, and the fiscal
# settings used to issue them. Like charges, every invoice has a stable
# external reference: a lost response is resolved by looking the invoice up,
# never by creating a second one.
class CreateServiceInvoices < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :fiscal_settings do |t|
      t.string :municipal_service_code, null: false
      t.string :municipal_service_name, null: false
      t.decimal :iss_rate, precision: 5, scale: 2, null: false
      t.boolean :retain_iss, null: false, default: false
      t.boolean :auto_issue_on_payment, null: false, default: false
      t.string :default_description
    end
    add_index :fiscal_settings, :organization_id, unique: true, name: "index_fiscal_settings_single"
    add_check_constraint :fiscal_settings, "iss_rate >= 0 AND iss_rate <= 5", name: "fiscal_settings_iss_rate"

    create_tenant_table :service_invoices do |t|
      t.string :provider, null: false
      t.string :external_reference, null: false
      t.string :external_id
      t.string :status, null: false, default: "pending"
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.text :description, null: false
      t.string :number
      t.string :verification_code
      t.string :pdf_url
      t.string :xml_url
      t.text :last_error
      t.integer :attempts, null: false, default: 0
      t.datetime :issued_at
      t.datetime :last_synced_at
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_reference :service_invoices, :receivables, column: :receivable_id, null: false
    add_tenant_reference :service_invoices, :memberships, column: :requested_by_membership_id, index: false
    add_index :service_invoices, %i[organization_id external_reference], unique: true
    add_index :service_invoices, :receivable_id, unique: true,
      where: "(status)::text = ANY (ARRAY['pending'::text, 'scheduled'::text, 'authorized'::text, 'unknown'::text])",
      name: "index_service_invoices_single_valid"
    add_inclusion_constraint :service_invoices, :status, %w[pending scheduled authorized unknown error canceling canceled],
      name: "service_invoices_status"
    add_inclusion_constraint :service_invoices, :provider, %w[simulator asaas], name: "service_invoices_provider"
    add_check_constraint :service_invoices, "amount > 0 AND attempts >= 0", name: "service_invoices_values"
  end
end
