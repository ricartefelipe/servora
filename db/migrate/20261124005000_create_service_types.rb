# frozen_string_literal: true

# Service types define the checklist that must be answered before a work order
# of that type can be completed.
class CreateServiceTypes < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :service_types do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
    end
    add_index :service_types, %i[organization_id name], unique: true

    create_tenant_table :service_type_checklist_items do |t|
      t.string :label, null: false
      t.string :response_kind, null: false, default: "check"
      t.boolean :required, null: false, default: true
      t.integer :position, null: false, default: 0
    end
    add_tenant_reference :service_type_checklist_items, :service_types, column: :service_type_id, null: false, on_delete: :cascade
    add_inclusion_constraint :service_type_checklist_items, :response_kind, %w[check text number], name: "checklist_items_kind"
  end
end
