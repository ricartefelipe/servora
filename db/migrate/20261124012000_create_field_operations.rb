# frozen_string_literal: true

# Operations sent by the field app (possibly queued offline). The operation id
# is generated on the device; storing the outcome makes every resend return
# the original result instead of applying the change again.
class CreateFieldOperations < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :field_operations, timestamps: :created_only do |t|
      t.uuid :operation_id, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.jsonb :result, null: false, default: {}
    end
    add_tenant_reference :field_operations, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :field_operations, :memberships, column: :membership_id, null: false, index: false
    add_index :field_operations, %i[organization_id operation_id], unique: true
    add_inclusion_constraint :field_operations, :kind, %w[time_entry technical_report checklist], name: "field_operations_kind"
    add_inclusion_constraint :field_operations, :status, %w[applied conflict rejected], name: "field_operations_status"
  end
end
