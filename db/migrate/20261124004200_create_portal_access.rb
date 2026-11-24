# frozen_string_literal: true

# Customer portal access. A grant is a single-use, expiring link sent by
# e-mail; it is exchanged (POST) for a portal session stored as an HttpOnly
# cookie. Only digests of the tokens are stored. Both are revocable.
class CreatePortalAccess < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    create_tenant_table :portal_access_grants do |t|
      t.string :purpose, null: false
      t.string :token_digest, null: false
      t.uuid :quote_id
      t.uuid :outbox_event_id
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
    end
    add_tenant_reference :portal_access_grants, :customer_contacts, column: :contact_id, null: false
    add_tenant_foreign_key :portal_access_grants, :quotes, column: :quote_id
    add_index :portal_access_grants, :token_digest, unique: true
    add_index :portal_access_grants, %i[organization_id outbox_event_id contact_id], unique: true,
      where: "outbox_event_id IS NOT NULL", name: "index_portal_grants_per_event"
    add_inclusion_constraint :portal_access_grants, :purpose, %w[quote_review portal], name: "portal_access_grants_purpose"

    create_tenant_table :portal_sessions do |t|
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at
      t.inet :ip_address
      t.string :user_agent, limit: 255
    end
    add_tenant_reference :portal_sessions, :customer_contacts, column: :contact_id, null: false
    add_tenant_reference :portal_sessions, :portal_access_grants, column: :grant_id, null: false, index: false
    add_index :portal_sessions, :token_digest, unique: true

    execute <<~SQL
      CREATE FUNCTION servora_resolve_portal_grant(p_token_digest text) RETURNS uuid
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$ SELECT organization_id FROM portal_access_grants WHERE token_digest = p_token_digest $$;

      CREATE FUNCTION servora_resolve_portal_session(p_token_digest text) RETURNS uuid
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$
          SELECT organization_id FROM portal_sessions
          WHERE token_digest = p_token_digest AND revoked_at IS NULL AND expires_at > clock_timestamp()
        $$;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS servora_resolve_portal_session(text);
      DROP FUNCTION IF EXISTS servora_resolve_portal_grant(text);
    SQL
    drop_table :portal_sessions
    drop_table :portal_access_grants
  end
end
