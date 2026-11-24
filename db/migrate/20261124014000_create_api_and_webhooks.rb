# frozen_string_literal: true

# Public API credentials, outbound webhook endpoints and deliveries, and
# inbound webhooks from the payment provider.
#
# * credential and inbound tokens are stored as digests; SECURITY DEFINER
#   functions resolve only the organization id from a digest, everything else
#   is loaded under RLS;
# * webhook deliveries are unique per (endpoint, event): the event id sent to
#   receivers is stable across retries;
# * inbound webhooks are persisted before acknowledgement and deduplicated by
#   the provider's event id.
class CreateApiAndWebhooks < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    create_tenant_table :api_credentials do |t|
      t.string :name, null: false
      t.string :token_prefix, null: false
      t.string :token_digest, null: false
      t.string :scopes, array: true, null: false, default: []
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
    end
    add_tenant_reference :api_credentials, :memberships, column: :created_by_membership_id, null: false, index: false
    add_index :api_credentials, :token_digest, unique: true
    add_check_constraint :api_credentials, "cardinality(scopes) > 0", name: "api_credentials_scopes"

    create_tenant_table :api_idempotency_keys, timestamps: :created_only do |t|
      t.string :key, null: false
      t.string :request_digest, null: false
      t.integer :response_status, null: false
      t.jsonb :response_body, null: false
    end
    add_tenant_reference :api_idempotency_keys, :api_credentials, column: :api_credential_id, null: false, index: false
    add_index :api_idempotency_keys, %i[api_credential_id key], unique: true

    create_tenant_table :webhook_endpoints do |t|
      t.string :url, null: false
      t.string :description
      t.text :secret, null: false
      t.string :events, array: true, null: false, default: []
      t.boolean :active, null: false, default: true
    end
    add_check_constraint :webhook_endpoints, "cardinality(events) > 0", name: "webhook_endpoints_events"

    create_tenant_table :webhook_deliveries do |t|
      t.uuid :event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :last_response_code
      t.text :last_error
      t.datetime :delivered_at
      t.datetime :last_attempt_at
    end
    add_tenant_reference :webhook_deliveries, :webhook_endpoints, column: :webhook_endpoint_id, null: false, index: false
    add_index :webhook_deliveries, %i[webhook_endpoint_id event_id], unique: true
    add_index :webhook_deliveries, %i[organization_id status created_at]
    add_inclusion_constraint :webhook_deliveries, :status, %w[pending delivered failed], name: "webhook_deliveries_status"

    add_column :payment_integrations, :webhook_token_digest, :string
    add_index :payment_integrations, :webhook_token_digest, unique: true, where: "webhook_token_digest IS NOT NULL"

    create_tenant_table :inbound_webhooks do |t|
      t.string :provider, null: false
      t.string :external_event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false
      t.string :status, null: false, default: "received"
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :processed_at
    end
    add_index :inbound_webhooks, %i[organization_id provider external_event_id], unique: true,
      name: "index_inbound_webhooks_dedup"
    add_inclusion_constraint :inbound_webhooks, :status, %w[received processed ignored failed], name: "inbound_webhooks_status"

    execute <<~SQL
      CREATE FUNCTION servora_resolve_api_credential(p_token_digest text) RETURNS uuid
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$
          SELECT organization_id FROM api_credentials
          WHERE token_digest = p_token_digest AND revoked_at IS NULL
            AND (expires_at IS NULL OR expires_at > clock_timestamp())
        $$;

      CREATE FUNCTION servora_resolve_payment_webhook(p_token_digest text) RETURNS uuid
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$
          SELECT organization_id FROM payment_integrations WHERE webhook_token_digest = p_token_digest
        $$;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS servora_resolve_payment_webhook(text);
      DROP FUNCTION IF EXISTS servora_resolve_api_credential(text);
    SQL
    drop_table :inbound_webhooks
    remove_column :payment_integrations, :webhook_token_digest
    drop_table :webhook_deliveries
    drop_table :webhook_endpoints
    drop_table :api_idempotency_keys
    drop_table :api_credentials
  end
end
