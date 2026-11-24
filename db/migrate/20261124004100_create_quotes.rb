# frozen_string_literal: true

# Quotes are versioned. Once a version leaves "draft" its items, totals and
# terms are frozen by triggers: catalog or price changes can never alter what
# was sent to (or approved by) the customer.
class CreateQuotes < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  QUOTE_STATUSES = %w[draft sent approved rejected expired converted canceled].freeze
  VERSION_STATUSES = %w[draft sent approved rejected superseded expired].freeze

  def up
    create_tenant_table :quotes do |t|
      t.string :number, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.uuid :customer_id, null: false
      t.uuid :service_location_id, null: false
      t.uuid :current_version_id
      t.uuid :approved_version_id
      t.integer :lock_version, null: false, default: 0
    end
    add_tenant_foreign_key :quotes, :customers, column: :customer_id
    add_foreign_key :quotes, :service_locations, column: %i[organization_id customer_id service_location_id],
      primary_key: %i[organization_id customer_id id], name: "fk_quotes_location_of_customer"
    add_tenant_reference :quotes, :memberships, column: :created_by_membership_id, null: false, index: false
    add_index :quotes, %i[organization_id number], unique: true
    add_index :quotes, %i[organization_id status created_at]
    add_index :quotes, %i[organization_id customer_id]
    add_inclusion_constraint :quotes, :status, QUOTE_STATUSES, name: "quotes_status"

    create_tenant_table :quote_versions do |t|
      t.integer :version_number, null: false
      t.string :status, null: false, default: "draft"
      t.date :valid_until, null: false
      t.text :payment_terms
      t.text :notes
      t.decimal :subtotal, precision: 14, scale: 2, null: false, default: 0
      t.decimal :discount_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :total, precision: 14, scale: 2, null: false, default: 0
      t.jsonb :snapshot
      t.string :content_digest
      t.datetime :sent_at
      t.datetime :decided_at
      t.string :decision_channel
      t.uuid :decided_by_contact_id
      t.uuid :decided_by_membership_id
      t.inet :decision_ip
      t.string :decision_user_agent
      t.text :decision_note
    end
    add_tenant_reference :quote_versions, :quotes, column: :quote_id, null: false, index: false
    add_index :quote_versions, %i[organization_id quote_id version_number], unique: true, name: "index_quote_versions_number"
    add_inclusion_constraint :quote_versions, :status, VERSION_STATUSES, name: "quote_versions_status"
    add_check_constraint :quote_versions,
      "discount_amount >= 0 AND discount_amount <= subtotal AND total = subtotal - discount_amount",
      name: "quote_versions_totals"
    add_check_constraint :quote_versions,
      "status = 'draft' OR (snapshot IS NOT NULL AND content_digest IS NOT NULL AND sent_at IS NOT NULL)",
      name: "quote_versions_frozen_content"
    # Written in PostgreSQL's canonical form so the dump text is stable.
    add_check_constraint :quote_versions,
      "(status)::text <> ALL (ARRAY['approved'::text, 'rejected'::text]) OR " \
      "(decided_at IS NOT NULL AND (decided_by_contact_id IS NOT NULL OR decided_by_membership_id IS NOT NULL))",
      name: "quote_versions_decision_evidence"
    add_tenant_foreign_key :quote_versions, :customer_contacts, column: :decided_by_contact_id
    add_tenant_foreign_key :quote_versions, :memberships, column: :decided_by_membership_id
    add_tenant_foreign_key :quotes, :quote_versions, column: :current_version_id
    add_tenant_foreign_key :quotes, :quote_versions, column: :approved_version_id

    create_tenant_table :quote_items do |t|
      t.string :kind, null: false
      t.string :description, null: false
      t.string :unit, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :unit_price, precision: 14, scale: 2, null: false
      t.decimal :unit_cost, precision: 14, scale: 4
      t.decimal :discount_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal :line_total, precision: 14, scale: 2, null: false
      t.integer :position, null: false, default: 0
    end
    add_tenant_reference :quote_items, :quote_versions, column: :quote_version_id, null: false, on_delete: :cascade
    add_tenant_reference :quote_items, :catalog_items, column: :catalog_item_id
    add_inclusion_constraint :quote_items, :kind, %w[service part other], name: "quote_items_kind"
    add_check_constraint :quote_items, "quantity > 0 AND unit_price >= 0 AND discount_amount >= 0", name: "quote_items_values"
    add_check_constraint :quote_items,
      "line_total = round(quantity * unit_price, 2) - discount_amount AND line_total >= 0",
      name: "quote_items_line_total"

    # Negotiation history (append-only).
    create_tenant_table :quote_events, timestamps: :created_only do |t|
      t.string :kind, null: false
      t.string :actor_type, null: false
      t.string :actor_label
      t.text :note
      t.jsonb :metadata, null: false, default: {}
    end
    add_tenant_reference :quote_events, :quotes, column: :quote_id, null: false
    add_tenant_reference :quote_events, :quote_versions, column: :quote_version_id, index: false

    execute <<~SQL
      CREATE FUNCTION servora_guard_frozen_quote_items() RETURNS trigger
        LANGUAGE plpgsql AS $$
        DECLARE
          version_status text;
        BEGIN
          SELECT status INTO version_status FROM quote_versions
          WHERE id = COALESCE(NEW.quote_version_id, OLD.quote_version_id);
          -- NULL: the parent draft version is being deleted (cascade).
          IF version_status IS NOT NULL AND version_status <> 'draft' THEN
            RAISE EXCEPTION 'quote version is frozen (status %)', version_status
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;
          RETURN COALESCE(NEW, OLD);
        END
      $$;

      CREATE TRIGGER quote_items_frozen
        BEFORE INSERT OR UPDATE OR DELETE ON quote_items
        FOR EACH ROW EXECUTE FUNCTION servora_guard_frozen_quote_items();

      CREATE FUNCTION servora_guard_frozen_quote_versions() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
          IF OLD.status <> 'draft' AND (
               NEW.quote_id IS DISTINCT FROM OLD.quote_id OR
               NEW.version_number IS DISTINCT FROM OLD.version_number OR
               NEW.valid_until IS DISTINCT FROM OLD.valid_until OR
               NEW.payment_terms IS DISTINCT FROM OLD.payment_terms OR
               NEW.notes IS DISTINCT FROM OLD.notes OR
               NEW.subtotal IS DISTINCT FROM OLD.subtotal OR
               NEW.discount_amount IS DISTINCT FROM OLD.discount_amount OR
               NEW.total IS DISTINCT FROM OLD.total OR
               NEW.snapshot IS DISTINCT FROM OLD.snapshot OR
               NEW.content_digest IS DISTINCT FROM OLD.content_digest OR
               NEW.sent_at IS DISTINCT FROM OLD.sent_at) THEN
            RAISE EXCEPTION 'sent quote versions are immutable'
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;
          IF OLD.status IN ('approved', 'rejected') AND (
               NEW.decided_at IS DISTINCT FROM OLD.decided_at OR
               NEW.decided_by_contact_id IS DISTINCT FROM OLD.decided_by_contact_id OR
               NEW.decided_by_membership_id IS DISTINCT FROM OLD.decided_by_membership_id OR
               NEW.decision_ip IS DISTINCT FROM OLD.decision_ip OR
               NEW.decision_note IS DISTINCT FROM OLD.decision_note) THEN
            RAISE EXCEPTION 'quote decisions are immutable'
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;
          RETURN NEW;
        END
      $$;

      CREATE TRIGGER quote_versions_frozen
        BEFORE UPDATE ON quote_versions
        FOR EACH ROW EXECUTE FUNCTION servora_guard_frozen_quote_versions();

      CREATE FUNCTION servora_forbid_sent_quote_version_delete() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
          RAISE EXCEPTION 'sent quote versions cannot be deleted'
            USING ERRCODE = 'integrity_constraint_violation';
        END
      $$;

      CREATE TRIGGER quote_versions_no_delete_after_draft
        BEFORE DELETE ON quote_versions
        FOR EACH ROW WHEN (OLD.status <> 'draft')
        EXECUTE FUNCTION servora_forbid_sent_quote_version_delete();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS quote_versions_no_delete_after_draft ON quote_versions;
      DROP TRIGGER IF EXISTS quote_versions_frozen ON quote_versions;
      DROP TRIGGER IF EXISTS quote_items_frozen ON quote_items;
      DROP FUNCTION IF EXISTS servora_forbid_sent_quote_version_delete();
      DROP FUNCTION IF EXISTS servora_guard_frozen_quote_versions();
      DROP FUNCTION IF EXISTS servora_guard_frozen_quote_items();
    SQL
    remove_foreign_key :quotes, column: %i[organization_id approved_version_id]
    remove_foreign_key :quotes, column: %i[organization_id current_version_id]
    drop_table :quote_events
    drop_table :quote_items
    drop_table :quote_versions
    drop_table :quotes
  end
end
