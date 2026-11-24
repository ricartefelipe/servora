# frozen_string_literal: true

# Labor records. The hourly cost in force when the entry is recorded is
# stored with it, so later changes to a technician's cost never rewrite the
# result of past work orders.
class CreateTimeEntries < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :time_entries do |t|
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.integer :minutes, null: false
      t.decimal :hourly_cost, precision: 14, scale: 4
      t.decimal :labor_cost, precision: 14, scale: 2
      t.string :source, null: false, default: "manual"
      t.text :notes
      t.uuid :client_operation_id
    end
    add_tenant_reference :time_entries, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :time_entries, :visits, column: :visit_id, index: false
    add_tenant_reference :time_entries, :memberships, column: :membership_id, null: false
    add_index :time_entries, %i[organization_id client_operation_id], unique: true, where: "client_operation_id IS NOT NULL",
      name: "index_time_entries_operation"
    add_inclusion_constraint :time_entries, :source, %w[manual field offline], name: "time_entries_source"
    add_check_constraint :time_entries, "started_at < ended_at AND minutes > 0", name: "time_entries_period"
  end
end
