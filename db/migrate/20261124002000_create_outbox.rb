# frozen_string_literal: true

# Transactional Outbox.
#
# Business changes and their events are written in the same transaction. The
# dispatcher claims due events through servora_claim_outbox_events(), which
# runs with the owner's rights (events of every organization) but returns only
# identifiers; each event is then processed inside its own tenant context.
#
# Claiming uses FOR UPDATE SKIP LOCKED plus a lease (locked_until): a crashed
# worker's events become claimable again once the lease expires. Time checks
# use clock_timestamp() (wall clock), not now() (start of the transaction).
class CreateOutbox < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def up
    create_tenant_table :outbox_events do |t|
      t.string :event_type, null: false
      t.string :aggregate_type, null: false
      t.uuid :aggregate_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :dedup_key
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, null: false, default: 8
      t.datetime :available_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.string :locked_by
      t.datetime :locked_until
      t.datetime :processed_at
      t.string :last_error
      t.string :request_id
    end

    add_index :outbox_events, %i[organization_id dedup_key], unique: true, where: "dedup_key IS NOT NULL"
    add_index :outbox_events, %i[available_at id], where: "status = 'pending'", name: "index_outbox_events_due"
    add_index :outbox_events, :locked_until, where: "status = 'processing'", name: "index_outbox_events_leases"
    add_index :outbox_events, %i[organization_id status created_at]
    add_inclusion_constraint :outbox_events, :status, %w[pending processing processed dead], name: "outbox_events_status"
    add_check_constraint :outbox_events, "attempts >= 0 AND max_attempts BETWEEN 1 AND 50", name: "outbox_events_attempts"

    create_tenant_table :outbox_event_failures, timestamps: :created_only do |t|
      t.integer :attempt, null: false
      t.string :error_class, null: false
      t.string :error_message
      t.boolean :transient, null: false
    end
    add_tenant_reference :outbox_event_failures, :outbox_events, column: :outbox_event_id, null: false

    execute <<~SQL
      CREATE FUNCTION servora_claim_outbox_events(p_worker text, p_limit integer, p_lease_seconds integer)
        RETURNS TABLE (event_id uuid, organization_id uuid)
        LANGUAGE sql VOLATILE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$
          WITH candidates AS (
            SELECT e.id
            FROM outbox_events e
            WHERE (e.status = 'pending' AND e.available_at <= clock_timestamp())
               OR (e.status = 'processing' AND e.locked_until < clock_timestamp())
            ORDER BY e.available_at, e.id
            LIMIT LEAST(GREATEST(p_limit, 1), 100)
            FOR UPDATE SKIP LOCKED
          )
          UPDATE outbox_events e
          SET status = 'processing',
              locked_by = left(p_worker, 120),
              locked_until = clock_timestamp() + make_interval(secs => LEAST(GREATEST(p_lease_seconds, 10), 900)),
              attempts = e.attempts + 1,
              updated_at = clock_timestamp()
          FROM candidates c
          WHERE e.id = c.id
          RETURNING e.id, e.organization_id
        $$;

      CREATE FUNCTION servora_outbox_backlog()
        RETURNS TABLE (status text, total bigint, oldest_available_at timestamptz)
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$
          SELECT e.status::text, count(*), min(e.available_at)
          FROM outbox_events e
          WHERE e.status IN ('pending', 'processing', 'dead')
          GROUP BY e.status
        $$;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS servora_outbox_backlog()"
    execute "DROP FUNCTION IF EXISTS servora_claim_outbox_events(text, integer, integer)"
    drop_table :outbox_event_failures
    drop_table :outbox_events
  end
end
