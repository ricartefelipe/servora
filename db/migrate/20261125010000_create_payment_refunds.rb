# frozen_string_literal: true

# Execution of refunds. Every refund recorded on a receivable gets a row here:
# refunds of provider charges are sent to the provider (after commit, outside
# transactions); refunds of manual payments are flagged for the finance team.
#
# Refunds are not idempotent at the provider (partial refunds may repeat), so a
# lost response never triggers an automatic resend: the refund stays "unknown"
# until someone verifies it at the provider.
class CreatePaymentRefunds < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :payment_refunds do |t|
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.text :reason, null: false
      t.string :status, null: false
      t.string :external_id
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :submitted_at
      t.datetime :resolved_at
    end
    add_tenant_reference :payment_refunds, :payments, column: :payment_id, null: false
    add_tenant_reference :payment_refunds, :receivables, column: :receivable_id, null: false, index: false
    add_tenant_reference :payment_refunds, :memberships, column: :requested_by_membership_id, index: false
    add_tenant_reference :payment_refunds, :memberships, column: :resolved_by_membership_id, index: false
    add_index :payment_refunds, %i[organization_id status]
    add_inclusion_constraint :payment_refunds, :status, %w[manual pending accepted unknown failed], name: "payment_refunds_status"
    add_check_constraint :payment_refunds, "amount > 0 AND attempts >= 0", name: "payment_refunds_values"
  end
end
