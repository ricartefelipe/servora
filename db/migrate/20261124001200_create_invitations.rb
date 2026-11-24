# frozen_string_literal: true

class CreateInvitations < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    create_tenant_table :invitations do |t|
      t.string :email, null: false
      t.string :role, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.references :accepted_user, type: :uuid, foreign_key: { to_table: :users }, index: false
      t.datetime :revoked_at
    end
    add_tenant_reference :invitations, :memberships, column: :invited_by_membership_id, null: false

    add_index :invitations, :token_digest, unique: true
    add_index :invitations, %i[organization_id email], unique: true,
      where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_invitations_pending_email"
    add_check_constraint :invitations, "NOT (accepted_at IS NOT NULL AND revoked_at IS NOT NULL)",
      name: "invitations_single_outcome"
    add_check_constraint :invitations, "email = lower(email)", name: "invitations_email_lowercase"

    # Resolves the organization of an invitation from the token digest only.
    # Runs as the owner (bypassing RLS) and returns nothing but the tenant id;
    # the invitation itself is then read under the tenant's RLS context.
    execute <<~SQL
      CREATE FUNCTION servora_resolve_invitation(p_token_digest text) RETURNS uuid
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$ SELECT organization_id FROM invitations WHERE token_digest = p_token_digest $$;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS servora_resolve_invitation(text)"
    drop_table :invitations
  end
end
