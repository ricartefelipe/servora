# frozen_string_literal: true

# Append-only audit trail. The application role has no UPDATE/DELETE on this
# table (Servora::DatabasePrivileges), so recorded history cannot be rewritten.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :audit_events, timestamps: :created_only do |t|
      t.string :actor_type, null: false
      t.uuid :actor_user_id
      t.uuid :actor_membership_id
      t.string :actor_label
      t.string :action, null: false
      t.string :auditable_type
      t.uuid :auditable_id
      t.jsonb :changeset, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
    end

    add_index :audit_events, %i[organization_id created_at], order: { created_at: :desc }
    add_index :audit_events, %i[organization_id auditable_type auditable_id]
    add_index :audit_events, %i[organization_id action]
    add_inclusion_constraint :audit_events, :actor_type, %w[user portal_contact api_credential system],
      name: "audit_events_actor_type"
  end
end
