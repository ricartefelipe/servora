SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: servora_active_organizations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_active_organizations() RETURNS TABLE(organization_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ SELECT id FROM organizations WHERE status = 'active' ORDER BY id $$;


--
-- Name: servora_claim_outbox_events(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_claim_outbox_events(p_worker text, p_limit integer, p_lease_seconds integer) RETURNS TABLE(event_id uuid, organization_id uuid)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: servora_current_organization_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_current_organization_id() RETURNS uuid
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$ SELECT NULLIF(current_setting('servora.organization_id', true), '')::uuid $$;


--
-- Name: servora_current_user_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_current_user_id() RETURNS uuid
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$ SELECT NULLIF(current_setting('servora.user_id', true), '')::uuid $$;


--
-- Name: servora_forbid_sent_quote_version_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_forbid_sent_quote_version_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    RAISE EXCEPTION 'sent quote versions cannot be deleted'
      USING ERRCODE = 'integrity_constraint_violation';
  END
$$;


--
-- Name: servora_guard_frozen_quote_items(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_guard_frozen_quote_items() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: servora_guard_frozen_quote_versions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_guard_frozen_quote_versions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: servora_guard_stock_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_guard_stock_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    movement stock_movements%ROWTYPE;
    previous_on_hand numeric := 0;
    previous_reserved numeric := 0;
    on_hand_delta numeric := 0;
    reserved_delta numeric := 0;
  BEGIN
    IF TG_OP = 'INSERT' AND NEW.last_movement_id IS NULL THEN
      IF NEW.on_hand <> 0 OR NEW.reserved <> 0 THEN
        RAISE EXCEPTION 'stock balances start empty; quantities change only through movements'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;
      RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.on_hand = OLD.on_hand AND NEW.reserved = OLD.reserved
       AND NEW.average_cost = OLD.average_cost AND NEW.last_movement_id IS NOT DISTINCT FROM OLD.last_movement_id THEN
      RETURN NEW;
    END IF;

    IF NEW.last_movement_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.last_movement_id IS NOT DISTINCT FROM OLD.last_movement_id) THEN
      RAISE EXCEPTION 'stock balance change requires a new movement'
        USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    SELECT * INTO movement FROM stock_movements WHERE id = NEW.last_movement_id;
    IF NOT FOUND
       OR movement.warehouse_id <> NEW.warehouse_id
       OR movement.catalog_item_id <> NEW.catalog_item_id
       OR movement.on_hand_after <> NEW.on_hand
       OR movement.reserved_after <> NEW.reserved
       OR movement.average_cost_after <> NEW.average_cost THEN
      RAISE EXCEPTION 'stock balance does not match its movement'
        USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    IF TG_OP = 'UPDATE' THEN
      previous_on_hand := OLD.on_hand;
      previous_reserved := OLD.reserved;
    END IF;

    CASE movement.kind
      WHEN 'entry', 'return', 'transfer_in', 'adjustment_in' THEN
        on_hand_delta := movement.quantity;
      WHEN 'transfer_out', 'adjustment_out' THEN
        on_hand_delta := -movement.quantity;
      WHEN 'reservation' THEN
        reserved_delta := movement.quantity;
      WHEN 'reservation_release' THEN
        reserved_delta := -movement.quantity;
      WHEN 'consumption' THEN
        on_hand_delta := -movement.quantity;
        IF movement.reservation_id IS NOT NULL THEN
          reserved_delta := -movement.quantity;
        END IF;
    END CASE;

    IF NEW.on_hand <> previous_on_hand + on_hand_delta OR NEW.reserved <> previous_reserved + reserved_delta THEN
      RAISE EXCEPTION 'stock balance change does not match the movement quantity'
        USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NEW;
  END
$$;


--
-- Name: servora_outbox_backlog(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_outbox_backlog() RETURNS TABLE(status text, total bigint, oldest_available_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT e.status::text, count(*), min(e.available_at)
    FROM outbox_events e
    WHERE e.status IN ('pending', 'processing', 'dead')
    GROUP BY e.status
  $$;


--
-- Name: servora_resolve_api_credential(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_resolve_api_credential(p_token_digest text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT organization_id FROM api_credentials
    WHERE token_digest = p_token_digest AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at > clock_timestamp())
  $$;


--
-- Name: servora_resolve_invitation(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_resolve_invitation(p_token_digest text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ SELECT organization_id FROM invitations WHERE token_digest = p_token_digest $$;


--
-- Name: servora_resolve_payment_webhook(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_resolve_payment_webhook(p_token_digest text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT organization_id FROM payment_integrations WHERE webhook_token_digest = p_token_digest
  $$;


--
-- Name: servora_resolve_portal_grant(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_resolve_portal_grant(p_token_digest text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ SELECT organization_id FROM portal_access_grants WHERE token_digest = p_token_digest $$;


--
-- Name: servora_resolve_portal_session(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_resolve_portal_session(p_token_digest text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT organization_id FROM portal_sessions
    WHERE token_digest = p_token_digest AND revoked_at IS NULL AND expires_at > clock_timestamp()
  $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid DEFAULT public.servora_current_organization_id() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid DEFAULT public.servora_current_organization_id() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) with time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid DEFAULT public.servora_current_organization_id() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: api_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_credentials (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    token_prefix character varying NOT NULL,
    token_digest character varying NOT NULL,
    scopes character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    last_used_at timestamp(6) with time zone,
    expires_at timestamp(6) with time zone,
    revoked_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    created_by_membership_id uuid NOT NULL,
    CONSTRAINT api_credentials_scopes CHECK ((cardinality(scopes) > 0))
);


--
-- Name: api_idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_idempotency_keys (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    key character varying NOT NULL,
    request_digest character varying NOT NULL,
    response_status integer NOT NULL,
    response_body jsonb NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    api_credential_id uuid NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    actor_type character varying NOT NULL,
    actor_user_id uuid,
    actor_membership_id uuid,
    actor_label character varying,
    action character varying NOT NULL,
    auditable_type character varying,
    auditable_id uuid,
    changeset jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT audit_events_actor_type CHECK (((actor_type)::text = ANY (ARRAY['user'::text, 'portal_contact'::text, 'api_credential'::text, 'system'::text])))
);


--
-- Name: business_hours; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_hours (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    weekday integer NOT NULL,
    start_minute integer NOT NULL,
    end_minute integer NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT business_hours_values CHECK (((weekday >= 0) AND (weekday <= 6) AND (start_minute >= 0) AND (end_minute <= 1440) AND (start_minute < end_minute)))
);


--
-- Name: catalog_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    name character varying NOT NULL,
    sku character varying,
    description text,
    unit character varying DEFAULT 'un'::character varying NOT NULL,
    unit_price numeric(14,2) DEFAULT 0.0 NOT NULL,
    unit_cost numeric(14,4),
    estimated_minutes integer,
    tracks_inventory boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT catalog_items_estimated_minutes CHECK (((estimated_minutes IS NULL) OR ((estimated_minutes >= 1) AND (estimated_minutes <= 10080)))),
    CONSTRAINT catalog_items_inventory_only_parts CHECK ((((kind)::text = 'part'::text) OR (NOT tracks_inventory))),
    CONSTRAINT catalog_items_kind CHECK (((kind)::text = ANY (ARRAY['service'::text, 'part'::text]))),
    CONSTRAINT catalog_items_money CHECK (((unit_price >= (0)::numeric) AND ((unit_cost IS NULL) OR (unit_cost >= (0)::numeric)))),
    CONSTRAINT catalog_items_unit CHECK (((unit)::text = ANY (ARRAY['un'::text, 'h'::text, 'min'::text, 'm'::text, 'm2'::text, 'm3'::text, 'kg'::text, 'l'::text, 'par'::text, 'cj'::text, 'vb'::text])))
);


--
-- Name: contract_service_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_service_types (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    contract_id uuid NOT NULL,
    service_type_id uuid NOT NULL
);


--
-- Name: contract_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_versions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    version_number integer NOT NULL,
    terms jsonb NOT NULL,
    reason text,
    created_by_membership_id uuid,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    contract_id uuid NOT NULL
);


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    number character varying NOT NULL,
    title character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    starts_on date NOT NULL,
    ends_on date,
    monthly_fee numeric(14,2) DEFAULT 0.0 NOT NULL,
    monthly_visit_limit integer,
    covers_parts boolean DEFAULT false NOT NULL,
    scope text,
    current_version integer DEFAULT 1 NOT NULL,
    activated_at timestamp(6) with time zone,
    suspended_at timestamp(6) with time zone,
    ended_at timestamp(6) with time zone,
    status_reason text,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    customer_id uuid NOT NULL,
    created_by_membership_id uuid,
    CONSTRAINT contracts_status CHECK (((status)::text = ANY (ARRAY['draft'::text, 'active'::text, 'suspended'::text, 'ended'::text]))),
    CONSTRAINT contracts_status_timestamps CHECK (((((status)::text <> 'active'::text) OR (activated_at IS NOT NULL)) AND (((status)::text <> 'suspended'::text) OR (suspended_at IS NOT NULL)) AND (((status)::text <> 'ended'::text) OR (ended_at IS NOT NULL)))),
    CONSTRAINT contracts_values CHECK ((((ends_on IS NULL) OR (ends_on >= starts_on)) AND (monthly_fee >= (0)::numeric) AND ((monthly_visit_limit IS NULL) OR (monthly_visit_limit > 0)) AND (current_version > 0)))
);


--
-- Name: customer_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_contacts (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    email character varying,
    phone character varying,
    "position" character varying,
    can_approve boolean DEFAULT false NOT NULL,
    can_follow boolean DEFAULT true NOT NULL,
    portal_enabled boolean DEFAULT false NOT NULL,
    archived_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    customer_id uuid NOT NULL,
    CONSTRAINT customer_contacts_portal_requires_email CHECK (((NOT portal_enabled) OR (email IS NOT NULL)))
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    name character varying NOT NULL,
    trade_name character varying,
    document character varying,
    email character varying,
    phone character varying,
    notes text,
    archived_at timestamp(6) with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT customers_kind CHECK (((kind)::text = ANY (ARRAY['individual'::text, 'company'::text])))
);


--
-- Name: equipment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.equipment (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    service_location_id uuid NOT NULL,
    equipment_type character varying NOT NULL,
    manufacturer character varying,
    model character varying,
    serial_number character varying,
    asset_tag character varying,
    capacity character varying,
    installed_on date,
    warranty_until date,
    warranty_notes character varying,
    operational_status character varying DEFAULT 'operational'::character varying NOT NULL,
    notes text,
    archived_at timestamp(6) with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT equipment_operational_status CHECK (((operational_status)::text = ANY (ARRAY['operational'::text, 'attention'::text, 'inoperative'::text, 'decommissioned'::text]))),
    CONSTRAINT equipment_warranty_after_installation CHECK (((warranty_until IS NULL) OR (installed_on IS NULL) OR (warranty_until >= installed_on)))
);


--
-- Name: equipment_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.equipment_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    from_customer_id uuid,
    to_customer_id uuid,
    from_location_id uuid,
    to_location_id uuid,
    from_status character varying,
    to_status character varying,
    description character varying,
    actor_membership_id uuid,
    occurred_at timestamp(6) with time zone NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    equipment_id uuid NOT NULL,
    CONSTRAINT equipment_events_kind CHECK (((kind)::text = ANY (ARRAY['registered'::text, 'relocated'::text, 'ownership_transferred'::text, 'status_changed'::text, 'archived'::text, 'restored'::text, 'maintenance'::text])))
);


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    category character varying NOT NULL,
    description character varying NOT NULL,
    amount numeric(14,2) NOT NULL,
    incurred_on date NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    recorded_by_membership_id uuid,
    CONSTRAINT expenses_amount CHECK ((amount > (0)::numeric)),
    CONSTRAINT expenses_category CHECK (((category)::text = ANY (ARRAY['travel'::text, 'toll'::text, 'parking'::text, 'meals'::text, 'outsourced'::text, 'materials'::text, 'other'::text])))
);


--
-- Name: field_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.field_operations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    operation_id uuid NOT NULL,
    kind character varying NOT NULL,
    status character varying NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    work_order_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    CONSTRAINT field_operations_kind CHECK (((kind)::text = ANY (ARRAY['time_entry'::text, 'technical_report'::text, 'checklist'::text]))),
    CONSTRAINT field_operations_status CHECK (((status)::text = ANY (ARRAY['applied'::text, 'conflict'::text, 'rejected'::text])))
);


--
-- Name: financial_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    amount numeric(14,2),
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    actor_membership_id uuid,
    actor_label character varying,
    occurred_at timestamp(6) with time zone NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    receivable_id uuid NOT NULL,
    payment_id uuid,
    CONSTRAINT financial_events_kind CHECK (((kind)::text = ANY (ARRAY['issued'::text, 'payment'::text, 'discount'::text, 'refund'::text, 'canceled'::text, 'charge_requested'::text, 'charge_submitted'::text, 'charge_confirmed'::text, 'charge_failed'::text, 'charge_unknown'::text, 'charge_canceled'::text])))
);


--
-- Name: holidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.holidays (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    date date NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: inbound_webhooks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_webhooks (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    provider character varying NOT NULL,
    external_event_id character varying NOT NULL,
    event_type character varying NOT NULL,
    payload jsonb NOT NULL,
    status character varying DEFAULT 'received'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    processed_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT inbound_webhooks_status CHECK (((status)::text = ANY (ARRAY['received'::text, 'processed'::text, 'ignored'::text, 'failed'::text])))
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    email character varying NOT NULL,
    role character varying NOT NULL,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) with time zone NOT NULL,
    accepted_at timestamp(6) with time zone,
    accepted_user_id uuid,
    revoked_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    invited_by_membership_id uuid NOT NULL,
    CONSTRAINT invitations_email_lowercase CHECK (((email)::text = lower((email)::text))),
    CONSTRAINT invitations_single_outcome CHECK ((NOT ((accepted_at IS NOT NULL) AND (revoked_at IS NOT NULL))))
);


--
-- Name: maintenance_occurrences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_occurrences (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    sequence integer NOT NULL,
    due_on date NOT NULL,
    generated_at timestamp(6) with time zone NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    maintenance_plan_id uuid NOT NULL,
    work_order_id uuid NOT NULL,
    CONSTRAINT maintenance_occurrences_sequence CHECK ((sequence >= 1))
);


--
-- Name: maintenance_plan_equipment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_plan_equipment (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    equipment_id uuid NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    maintenance_plan_id uuid NOT NULL
);


--
-- Name: maintenance_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_plans (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    title character varying NOT NULL,
    priority character varying DEFAULT 'normal'::character varying NOT NULL,
    frequency_unit character varying NOT NULL,
    frequency_interval integer DEFAULT 1 NOT NULL,
    schedule_mode character varying DEFAULT 'calendar'::character varying NOT NULL,
    anchor_date date NOT NULL,
    anchor_sequence integer DEFAULT 1 NOT NULL,
    last_sequence integer DEFAULT 0 NOT NULL,
    lead_days integer DEFAULT 7 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    instructions text,
    lock_version integer DEFAULT 0 NOT NULL,
    customer_id uuid NOT NULL,
    service_location_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    contract_id uuid NOT NULL,
    service_type_id uuid,
    created_by_membership_id uuid,
    CONSTRAINT maintenance_plans_mode CHECK (((schedule_mode)::text = ANY (ARRAY['calendar'::text, 'after_completion'::text]))),
    CONSTRAINT maintenance_plans_priority CHECK (((priority)::text = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
    CONSTRAINT maintenance_plans_unit CHECK (((frequency_unit)::text = ANY (ARRAY['week'::text, 'month'::text, 'year'::text]))),
    CONSTRAINT maintenance_plans_values CHECK (((frequency_interval >= 1) AND (frequency_interval <= 104) AND (lead_days >= 0) AND (lead_days <= 90) AND (anchor_sequence >= 1) AND (last_sequence >= 0) AND (anchor_sequence <= (last_sequence + 1))))
);


--
-- Name: material_consumptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.material_consumptions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    quantity numeric(14,3) NOT NULL,
    returned_quantity numeric(14,3) DEFAULT 0.0 NOT NULL,
    unit_cost numeric(14,4) NOT NULL,
    total_cost numeric(14,2) NOT NULL,
    idempotency_key character varying,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    catalog_item_id uuid NOT NULL,
    reservation_id uuid,
    movement_id uuid NOT NULL,
    CONSTRAINT material_consumptions_returns CHECK (((quantity > (0)::numeric) AND (returned_quantity >= (0)::numeric) AND (returned_quantity <= quantity)))
);


--
-- Name: membership_skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.membership_skills (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    membership_id uuid NOT NULL,
    skill_id uuid NOT NULL
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    job_title character varying,
    phone character varying,
    hourly_cost numeric(14,4),
    deactivated_at timestamp(6) with time zone,
    deactivated_by_user_id uuid,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT memberships_hourly_cost CHECK (((hourly_cost IS NULL) OR (hourly_cost >= (0)::numeric))),
    CONSTRAINT memberships_role CHECK (((role)::text = ANY (ARRAY['owner'::text, 'admin'::text, 'coordinator'::text, 'attendant'::text, 'technician'::text, 'finance'::text, 'auditor'::text]))),
    CONSTRAINT memberships_status CHECK (((status)::text = ANY (ARRAY['active'::text, 'deactivated'::text])))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    title character varying NOT NULL,
    body character varying,
    path character varying,
    read_at timestamp(6) with time zone,
    outbox_event_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    recipient_membership_id uuid NOT NULL
);


--
-- Name: organization_counters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_counters (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    scope character varying NOT NULL,
    year integer NOT NULL,
    value integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT uuidv7() NOT NULL,
    name character varying NOT NULL,
    legal_name character varying,
    document character varying,
    segment character varying DEFAULT 'other'::character varying NOT NULL,
    time_zone character varying DEFAULT 'America/Sao_Paulo'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    travel_buffer_minutes integer DEFAULT 30 NOT NULL,
    mfa_required_for_privileged boolean DEFAULT true NOT NULL,
    onboarding_completed_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT organizations_document_digits CHECK (((document IS NULL) OR ((document)::text ~ '^([0-9]{11}|[0-9A-Z]{12}[0-9]{2})$'::text))),
    CONSTRAINT organizations_status CHECK (((status)::text = ANY (ARRAY['active'::text, 'suspended'::text]))),
    CONSTRAINT organizations_travel_buffer CHECK (((travel_buffer_minutes >= 0) AND (travel_buffer_minutes <= 480)))
);


--
-- Name: outbox_event_failures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_event_failures (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    attempt integer NOT NULL,
    error_class character varying NOT NULL,
    error_message character varying,
    transient boolean NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    outbox_event_id uuid NOT NULL
);


--
-- Name: outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    event_type character varying NOT NULL,
    aggregate_type character varying NOT NULL,
    aggregate_id uuid NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    dedup_key character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 8 NOT NULL,
    available_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    locked_by character varying,
    locked_until timestamp(6) with time zone,
    processed_at timestamp(6) with time zone,
    last_error character varying,
    request_id character varying,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT outbox_events_attempts CHECK (((attempts >= 0) AND ((max_attempts >= 1) AND (max_attempts <= 50)))),
    CONSTRAINT outbox_events_status CHECK (((status)::text = ANY (ARRAY['pending'::text, 'processing'::text, 'processed'::text, 'dead'::text])))
);


--
-- Name: payment_charges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_charges (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    provider character varying NOT NULL,
    external_reference character varying NOT NULL,
    external_id character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    billing_type character varying NOT NULL,
    amount numeric(14,2) NOT NULL,
    due_on date NOT NULL,
    payment_url character varying,
    last_error text,
    attempts integer DEFAULT 0 NOT NULL,
    submitted_at timestamp(6) with time zone,
    confirmed_at timestamp(6) with time zone,
    last_synced_at timestamp(6) with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    receivable_id uuid NOT NULL,
    CONSTRAINT payment_charges_billing_type CHECK (((billing_type)::text = ANY (ARRAY['pix'::text, 'boleto'::text]))),
    CONSTRAINT payment_charges_provider CHECK (((provider)::text = ANY (ARRAY['simulator'::text, 'asaas'::text]))),
    CONSTRAINT payment_charges_status CHECK (((status)::text = ANY (ARRAY['pending'::text, 'submitted'::text, 'unknown'::text, 'confirmed'::text, 'failed'::text, 'canceled'::text]))),
    CONSTRAINT payment_charges_values CHECK (((amount > (0)::numeric) AND (attempts >= 0)))
);


--
-- Name: payment_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_integrations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    provider character varying DEFAULT 'simulator'::character varying NOT NULL,
    api_key text,
    default_billing_type character varying DEFAULT 'pix'::character varying NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    webhook_token_digest character varying,
    CONSTRAINT payment_integrations_billing_type CHECK (((default_billing_type)::text = ANY (ARRAY['pix'::text, 'boleto'::text]))),
    CONSTRAINT payment_integrations_credentials CHECK ((((provider)::text = 'simulator'::text) OR (api_key IS NOT NULL))),
    CONSTRAINT payment_integrations_provider CHECK (((provider)::text = ANY (ARRAY['simulator'::text, 'asaas'::text])))
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    amount numeric(14,2) NOT NULL,
    refunded_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    payment_method character varying NOT NULL,
    paid_at timestamp(6) with time zone NOT NULL,
    idempotency_key character varying,
    notes text,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    receivable_id uuid NOT NULL,
    payment_charge_id uuid,
    recorded_by_membership_id uuid,
    CONSTRAINT payments_method CHECK (((payment_method)::text = ANY (ARRAY['pix'::text, 'boleto'::text, 'transfer'::text, 'cash'::text, 'card_gateway'::text, 'other'::text]))),
    CONSTRAINT payments_values CHECK (((amount > (0)::numeric) AND (refunded_amount >= (0)::numeric) AND (refunded_amount <= amount)))
);


--
-- Name: plan_modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_modules (
    id uuid DEFAULT uuidv7() NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    monthly_price numeric(14,2) NOT NULL,
    "position" integer NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT plan_modules_price CHECK ((monthly_price >= (0)::numeric))
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id uuid DEFAULT uuidv7() NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    monthly_price numeric(14,2) NOT NULL,
    included_technicians integer NOT NULL,
    extra_technician_price numeric(14,2) NOT NULL,
    implementation_fee numeric(14,2) NOT NULL,
    modules character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    trial_days integer DEFAULT 14 NOT NULL,
    "position" integer NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT plans_values CHECK (((monthly_price >= (0)::numeric) AND (extra_technician_price >= (0)::numeric) AND (implementation_fee >= (0)::numeric) AND (included_technicians > 0) AND (trial_days >= 0)))
);


--
-- Name: portal_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_access_grants (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    purpose character varying NOT NULL,
    token_digest character varying NOT NULL,
    quote_id uuid,
    outbox_event_id uuid,
    expires_at timestamp(6) with time zone NOT NULL,
    used_at timestamp(6) with time zone,
    revoked_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    contact_id uuid NOT NULL,
    CONSTRAINT portal_access_grants_purpose CHECK (((purpose)::text = ANY (ARRAY['quote_review'::text, 'portal'::text])))
);


--
-- Name: portal_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) with time zone NOT NULL,
    last_seen_at timestamp(6) with time zone NOT NULL,
    revoked_at timestamp(6) with time zone,
    ip_address inet,
    user_agent character varying(255),
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    contact_id uuid NOT NULL,
    grant_id uuid NOT NULL
);


--
-- Name: quote_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quote_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    actor_type character varying NOT NULL,
    actor_label character varying,
    note text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    quote_id uuid NOT NULL,
    quote_version_id uuid
);


--
-- Name: quote_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quote_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    description character varying NOT NULL,
    unit character varying NOT NULL,
    quantity numeric(14,3) NOT NULL,
    unit_price numeric(14,2) NOT NULL,
    unit_cost numeric(14,4),
    discount_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    line_total numeric(14,2) NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    quote_version_id uuid NOT NULL,
    catalog_item_id uuid,
    CONSTRAINT quote_items_kind CHECK (((kind)::text = ANY (ARRAY['service'::text, 'part'::text, 'other'::text]))),
    CONSTRAINT quote_items_line_total CHECK (((line_total = (round((quantity * unit_price), 2) - discount_amount)) AND (line_total >= (0)::numeric))),
    CONSTRAINT quote_items_values CHECK (((quantity > (0)::numeric) AND (unit_price >= (0)::numeric) AND (discount_amount >= (0)::numeric)))
);


--
-- Name: quote_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quote_versions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    version_number integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    valid_until date NOT NULL,
    payment_terms text,
    notes text,
    subtotal numeric(14,2) DEFAULT 0.0 NOT NULL,
    discount_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    total numeric(14,2) DEFAULT 0.0 NOT NULL,
    snapshot jsonb,
    content_digest character varying,
    sent_at timestamp(6) with time zone,
    decided_at timestamp(6) with time zone,
    decision_channel character varying,
    decided_by_contact_id uuid,
    decided_by_membership_id uuid,
    decision_ip inet,
    decision_user_agent character varying,
    decision_note text,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    quote_id uuid NOT NULL,
    CONSTRAINT quote_versions_decision_evidence CHECK ((((status)::text <> ALL (ARRAY['approved'::text, 'rejected'::text])) OR ((decided_at IS NOT NULL) AND ((decided_by_contact_id IS NOT NULL) OR (decided_by_membership_id IS NOT NULL))))),
    CONSTRAINT quote_versions_frozen_content CHECK ((((status)::text = 'draft'::text) OR ((snapshot IS NOT NULL) AND (content_digest IS NOT NULL) AND (sent_at IS NOT NULL)))),
    CONSTRAINT quote_versions_status CHECK (((status)::text = ANY (ARRAY['draft'::text, 'sent'::text, 'approved'::text, 'rejected'::text, 'superseded'::text, 'expired'::text]))),
    CONSTRAINT quote_versions_totals CHECK (((discount_amount >= (0)::numeric) AND (discount_amount <= subtotal) AND (total = (subtotal - discount_amount))))
);


--
-- Name: quotes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quotes (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    number character varying NOT NULL,
    title character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    customer_id uuid NOT NULL,
    service_location_id uuid NOT NULL,
    current_version_id uuid,
    approved_version_id uuid,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    created_by_membership_id uuid NOT NULL,
    CONSTRAINT quotes_status CHECK (((status)::text = ANY (ARRAY['draft'::text, 'sent'::text, 'approved'::text, 'rejected'::text, 'expired'::text, 'converted'::text, 'canceled'::text])))
);


--
-- Name: receivables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receivables (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    number character varying NOT NULL,
    description character varying NOT NULL,
    amount numeric(14,2) NOT NULL,
    discount_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    paid_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    refunded_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    due_on date NOT NULL,
    settled_at timestamp(6) with time zone,
    canceled_at timestamp(6) with time zone,
    cancel_reason text,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    created_by_membership_id uuid,
    CONSTRAINT receivables_status CHECK (((status)::text = ANY (ARRAY['open'::text, 'partially_paid'::text, 'paid'::text, 'canceled'::text]))),
    CONSTRAINT receivables_status_consistency CHECK (((((status)::text = 'canceled'::text) = (canceled_at IS NOT NULL)) AND (((status)::text <> 'canceled'::text) OR (paid_amount = refunded_amount)) AND (((status)::text <> 'paid'::text) OR ((paid_amount - refunded_amount) = (amount - discount_amount))))),
    CONSTRAINT receivables_values CHECK (((amount > (0)::numeric) AND (discount_amount >= (0)::numeric) AND (paid_amount >= (0)::numeric) AND (refunded_amount >= (0)::numeric) AND (refunded_amount <= paid_amount) AND (discount_amount <= amount) AND ((paid_amount - refunded_amount) <= (amount - discount_amount))))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: service_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_locations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    street character varying NOT NULL,
    number character varying,
    complement character varying,
    district character varying,
    city character varying NOT NULL,
    state character varying(2) NOT NULL,
    postal_code character varying,
    access_instructions text,
    archived_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    customer_id uuid NOT NULL,
    CONSTRAINT service_locations_postal_code CHECK (((postal_code IS NULL) OR ((postal_code)::text ~ '^[0-9]{8}$'::text))),
    CONSTRAINT service_locations_state CHECK (((state)::text ~ '^[A-Z]{2}$'::text))
);


--
-- Name: service_type_checklist_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_type_checklist_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    label character varying NOT NULL,
    response_kind character varying DEFAULT 'check'::character varying NOT NULL,
    required boolean DEFAULT true NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    service_type_id uuid NOT NULL,
    CONSTRAINT checklist_items_kind CHECK (((response_kind)::text = ANY (ARRAY['check'::text, 'text'::text, 'number'::text])))
);


--
-- Name: service_type_skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_type_skills (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    service_type_id uuid NOT NULL,
    skill_id uuid NOT NULL
);


--
-- Name: service_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_types (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    description text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skills (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: sla_clock_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_clock_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    occurred_at timestamp(6) with time zone NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    sla_clock_id uuid NOT NULL,
    CONSTRAINT sla_clock_events_kind CHECK (((kind)::text = ANY (ARRAY['started'::text, 'paused'::text, 'resumed'::text, 'met'::text, 'breached'::text, 'warned'::text, 'canceled'::text, 'reopened'::text])))
);


--
-- Name: sla_clocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_clocks (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    metric character varying NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    target_seconds integer NOT NULL,
    consumed_seconds integer DEFAULT 0 NOT NULL,
    warning_percent integer NOT NULL,
    business_hours_only boolean NOT NULL,
    segment integer DEFAULT 1 NOT NULL,
    started_at timestamp(6) with time zone NOT NULL,
    running_since timestamp(6) with time zone,
    due_at timestamp(6) with time zone,
    warn_at timestamp(6) with time zone,
    stopped_at timestamp(6) with time zone,
    breached_at timestamp(6) with time zone,
    warned_at timestamp(6) with time zone,
    breach_notified_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    CONSTRAINT sla_clocks_consistency CHECK (((target_seconds > 0) AND (consumed_seconds >= 0) AND (segment >= 1) AND (((status)::text <> 'running'::text) OR ((running_since IS NOT NULL) AND (due_at IS NOT NULL))) AND (((status)::text = 'running'::text) OR (running_since IS NULL)))),
    CONSTRAINT sla_clocks_metric CHECK (((metric)::text = ANY (ARRAY['first_response'::text, 'resolution'::text]))),
    CONSTRAINT sla_clocks_status CHECK (((status)::text = ANY (ARRAY['running'::text, 'paused'::text, 'met'::text, 'breached'::text, 'canceled'::text])))
);


--
-- Name: sla_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_policies (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    priority character varying NOT NULL,
    first_response_minutes integer NOT NULL,
    resolution_minutes integer NOT NULL,
    business_hours_only boolean DEFAULT true NOT NULL,
    warning_percent integer DEFAULT 80 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT sla_policies_priority CHECK (((priority)::text = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
    CONSTRAINT sla_policies_values CHECK (((first_response_minutes > 0) AND (resolution_minutes > 0) AND (first_response_minutes <= resolution_minutes) AND (warning_percent >= 50) AND (warning_percent <= 95)))
);


--
-- Name: stock_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_balances (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    on_hand numeric(14,3) DEFAULT 0.0 NOT NULL,
    reserved numeric(14,3) DEFAULT 0.0 NOT NULL,
    average_cost numeric(14,4) DEFAULT 0.0 NOT NULL,
    minimum_quantity numeric(14,3) DEFAULT 0.0 NOT NULL,
    last_movement_id uuid,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    warehouse_id uuid NOT NULL,
    catalog_item_id uuid NOT NULL,
    CONSTRAINT stock_balances_values CHECK (((on_hand >= (0)::numeric) AND (reserved >= (0)::numeric) AND (reserved <= on_hand) AND (average_cost >= (0)::numeric) AND (minimum_quantity >= (0)::numeric)))
);


--
-- Name: stock_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_movements (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    quantity numeric(14,3) NOT NULL,
    unit_cost numeric(14,4) NOT NULL,
    total_cost numeric(14,2) NOT NULL,
    on_hand_after numeric(14,3) NOT NULL,
    reserved_after numeric(14,3) NOT NULL,
    average_cost_after numeric(14,4) NOT NULL,
    transfer_group_id uuid,
    reservation_id uuid,
    idempotency_key character varying,
    reason text,
    actor_membership_id uuid,
    occurred_at timestamp(6) with time zone NOT NULL,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    warehouse_id uuid NOT NULL,
    catalog_item_id uuid NOT NULL,
    work_order_id uuid,
    CONSTRAINT stock_movements_kind CHECK (((kind)::text = ANY (ARRAY['entry'::text, 'reservation'::text, 'reservation_release'::text, 'consumption'::text, 'return'::text, 'transfer_out'::text, 'transfer_in'::text, 'adjustment_in'::text, 'adjustment_out'::text]))),
    CONSTRAINT stock_movements_values CHECK (((quantity > (0)::numeric) AND (unit_cost >= (0)::numeric) AND (total_cost >= (0)::numeric) AND (on_hand_after >= (0)::numeric) AND (reserved_after >= (0)::numeric) AND (reserved_after <= on_hand_after) AND (average_cost_after >= (0)::numeric)))
);


--
-- Name: stock_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_reservations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    quantity numeric(14,3) NOT NULL,
    consumed_quantity numeric(14,3) DEFAULT 0.0 NOT NULL,
    released_quantity numeric(14,3) DEFAULT 0.0 NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    catalog_item_id uuid NOT NULL,
    CONSTRAINT stock_reservations_quantities CHECK (((quantity > (0)::numeric) AND (consumed_quantity >= (0)::numeric) AND (released_quantity >= (0)::numeric) AND ((consumed_quantity + released_quantity) <= quantity))),
    CONSTRAINT stock_reservations_status CHECK (((status)::text = ANY (ARRAY['active'::text, 'closed'::text])))
);


--
-- Name: subscription_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_invoices (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subscription_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    due_on date NOT NULL,
    amount numeric(14,2) NOT NULL,
    lines jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    provider character varying NOT NULL,
    external_reference character varying NOT NULL,
    external_id character varying,
    charge_status character varying DEFAULT 'pending'::character varying NOT NULL,
    payment_url character varying,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    paid_at timestamp(6) with time zone,
    last_synced_at timestamp(6) with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT subscription_invoices_charge_status CHECK (((charge_status)::text = ANY (ARRAY['pending'::text, 'submitted'::text, 'unknown'::text, 'confirmed'::text, 'failed'::text]))),
    CONSTRAINT subscription_invoices_status CHECK (((status)::text = ANY (ARRAY['open'::text, 'paid'::text, 'void'::text]))),
    CONSTRAINT subscription_invoices_values CHECK (((amount >= (0)::numeric) AND (period_end > period_start) AND (attempts >= 0)))
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    status character varying DEFAULT 'trialing'::character varying NOT NULL,
    trial_ends_on date,
    technician_seats integer NOT NULL,
    addon_modules character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    monthly_amount numeric(14,2) NOT NULL,
    implementation_fee numeric(14,2) DEFAULT 0.0 NOT NULL,
    implementation_status character varying DEFAULT 'not_applicable'::character varying NOT NULL,
    activated_at timestamp(6) with time zone,
    canceled_at timestamp(6) with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    plan_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    current_period_end date,
    CONSTRAINT subscriptions_implementation_status CHECK (((implementation_status)::text = ANY (ARRAY['not_applicable'::text, 'pending'::text, 'paid'::text, 'waived'::text]))),
    CONSTRAINT subscriptions_status CHECK (((status)::text = ANY (ARRAY['trialing'::text, 'active'::text, 'past_due'::text, 'canceled'::text]))),
    CONSTRAINT subscriptions_values CHECK (((technician_seats > 0) AND (monthly_amount >= (0)::numeric) AND (implementation_fee >= (0)::numeric) AND (((status)::text <> 'trialing'::text) OR (trial_ends_on IS NOT NULL))))
);


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_members (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    team_id uuid NOT NULL,
    membership_id uuid NOT NULL
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: technician_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_allocations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    period tstzrange NOT NULL,
    reason character varying,
    released_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    membership_id uuid NOT NULL,
    visit_id uuid,
    CONSTRAINT technician_allocations_half_open_period CHECK (((NOT isempty(period)) AND lower_inc(period) AND (NOT upper_inc(period)) AND (NOT lower_inf(period)) AND (NOT upper_inf(period)))),
    CONSTRAINT technician_allocations_kind CHECK (((kind)::text = ANY (ARRAY['visit'::text, 'absence'::text]))),
    CONSTRAINT technician_allocations_status CHECK (((status)::text = ANY (ARRAY['active'::text, 'released'::text]))),
    CONSTRAINT technician_allocations_visit_link CHECK ((((kind)::text = 'visit'::text) = (visit_id IS NOT NULL)))
);


--
-- Name: time_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_entries (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    started_at timestamp(6) with time zone NOT NULL,
    ended_at timestamp(6) with time zone NOT NULL,
    minutes integer NOT NULL,
    hourly_cost numeric(14,4),
    labor_cost numeric(14,2),
    source character varying DEFAULT 'manual'::character varying NOT NULL,
    notes text,
    client_operation_id uuid,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    visit_id uuid,
    membership_id uuid NOT NULL,
    CONSTRAINT time_entries_period CHECK (((started_at < ended_at) AND (minutes > 0))),
    CONSTRAINT time_entries_source CHECK (((source)::text = ANY (ARRAY['manual'::text, 'field'::text, 'offline'::text])))
);


--
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    ip_address inet,
    user_agent character varying(255),
    last_seen_at timestamp(6) with time zone NOT NULL,
    revoked_at timestamp(6) with time zone,
    revoke_reason character varying,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    name character varying NOT NULL,
    email character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) with time zone,
    confirmation_token character varying,
    confirmed_at timestamp(6) with time zone,
    confirmation_sent_at timestamp(6) with time zone,
    unconfirmed_email character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying,
    locked_at timestamp(6) with time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp(6) with time zone,
    last_sign_in_at timestamp(6) with time zone,
    current_sign_in_ip character varying,
    last_sign_in_ip character varying,
    otp_secret character varying,
    consumed_timestep integer,
    otp_required_for_login boolean DEFAULT false NOT NULL,
    otp_backup_codes character varying[],
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT users_email_lowercase CHECK (((email)::text = lower((email)::text))),
    CONSTRAINT users_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120)))
);


--
-- Name: visit_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.visit_transitions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    from_status character varying,
    to_status character varying NOT NULL,
    reason text,
    actor_label character varying,
    actor_membership_id uuid,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    visit_id uuid NOT NULL
);


--
-- Name: visits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.visits (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    status character varying DEFAULT 'scheduled'::character varying NOT NULL,
    scheduled_start timestamp(6) with time zone NOT NULL,
    scheduled_end timestamp(6) with time zone NOT NULL,
    travel_minutes integer DEFAULT 0 NOT NULL,
    started_at timestamp(6) with time zone,
    finished_at timestamp(6) with time zone,
    needs_return boolean DEFAULT false NOT NULL,
    notes text,
    outcome_note text,
    cancel_reason text,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    team_id uuid,
    scheduled_by_membership_id uuid NOT NULL,
    CONSTRAINT visits_period CHECK ((scheduled_start < scheduled_end)),
    CONSTRAINT visits_status CHECK (((status)::text = ANY (ARRAY['scheduled'::text, 'in_progress'::text, 'completed'::text, 'canceled'::text, 'no_show'::text]))),
    CONSTRAINT visits_travel CHECK (((travel_minutes >= 0) AND (travel_minutes <= 480)))
);


--
-- Name: warehouses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.warehouses (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    kind character varying DEFAULT 'central'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    custodian_membership_id uuid,
    CONSTRAINT warehouses_custodian CHECK ((((kind)::text = 'central'::text) OR (custodian_membership_id IS NOT NULL))),
    CONSTRAINT warehouses_kind CHECK (((kind)::text = ANY (ARRAY['central'::text, 'technician'::text, 'vehicle'::text])))
);


--
-- Name: webhook_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_deliveries (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    event_type character varying NOT NULL,
    payload jsonb NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_response_code integer,
    last_error text,
    delivered_at timestamp(6) with time zone,
    last_attempt_at timestamp(6) with time zone,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    webhook_endpoint_id uuid NOT NULL,
    CONSTRAINT webhook_deliveries_status CHECK (((status)::text = ANY (ARRAY['pending'::text, 'delivered'::text, 'failed'::text])))
);


--
-- Name: webhook_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_endpoints (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    url character varying NOT NULL,
    description character varying,
    secret text NOT NULL,
    events character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    CONSTRAINT webhook_endpoints_events CHECK ((cardinality(events) > 0))
);


--
-- Name: work_order_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_assignments (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    role character varying DEFAULT 'technician'::character varying NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    CONSTRAINT work_order_assignments_role CHECK (((role)::text = ANY (ARRAY['lead'::text, 'technician'::text])))
);


--
-- Name: work_order_checklist_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_checklist_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    label character varying NOT NULL,
    response_kind character varying NOT NULL,
    required boolean NOT NULL,
    "position" integer NOT NULL,
    response character varying,
    responded_at timestamp(6) with time zone,
    responded_by_membership_id uuid,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    CONSTRAINT work_order_checklist_kind CHECK (((response_kind)::text = ANY (ARRAY['check'::text, 'text'::text, 'number'::text])))
);


--
-- Name: work_order_equipment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_equipment (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    equipment_id uuid NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL
);


--
-- Name: work_order_evidences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_evidences (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    caption character varying,
    content_type character varying NOT NULL,
    byte_size bigint NOT NULL,
    original_filename character varying NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    uploaded_by_membership_id uuid NOT NULL,
    CONSTRAINT work_order_evidences_kind CHECK (((kind)::text = ANY (ARRAY['photo'::text, 'document'::text]))),
    CONSTRAINT work_order_evidences_size CHECK ((byte_size > 0))
);


--
-- Name: work_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    source character varying NOT NULL,
    description character varying NOT NULL,
    unit character varying NOT NULL,
    quantity numeric(14,3) NOT NULL,
    unit_price numeric(14,2) NOT NULL,
    unit_cost numeric(14,4),
    discount_amount numeric(14,2) DEFAULT 0.0 NOT NULL,
    line_total numeric(14,2) NOT NULL,
    authorization_status character varying NOT NULL,
    authorized_at timestamp(6) with time zone,
    authorization_channel character varying,
    authorization_note text,
    authorized_by_contact_id uuid,
    authorized_by_membership_id uuid,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    work_order_id uuid NOT NULL,
    catalog_item_id uuid,
    CONSTRAINT work_order_items_authorization_evidence CHECK ((((authorization_status)::text = 'pending'::text) OR ((authorized_at IS NOT NULL) AND (authorized_by_membership_id IS NOT NULL)))),
    CONSTRAINT work_order_items_authorization_status CHECK (((authorization_status)::text = ANY (ARRAY['authorized'::text, 'pending'::text, 'rejected'::text]))),
    CONSTRAINT work_order_items_kind CHECK (((kind)::text = ANY (ARRAY['service'::text, 'part'::text, 'other'::text]))),
    CONSTRAINT work_order_items_line_total CHECK (((line_total = (round((quantity * unit_price), 2) - discount_amount)) AND (line_total >= (0)::numeric))),
    CONSTRAINT work_order_items_source CHECK (((source)::text = ANY (ARRAY['quote'::text, 'additional'::text, 'preventive'::text, 'manual'::text]))),
    CONSTRAINT work_order_items_values CHECK (((quantity > (0)::numeric) AND (unit_price >= (0)::numeric) AND (discount_amount >= (0)::numeric)))
);


--
-- Name: work_order_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_reports (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    version_number integer NOT NULL,
    data jsonb NOT NULL,
    content_digest character varying NOT NULL,
    generated_by_membership_id uuid,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    work_order_id uuid NOT NULL
);


--
-- Name: work_order_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_order_transitions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    from_status character varying,
    to_status character varying NOT NULL,
    reason text,
    actor_label character varying,
    actor_membership_id uuid,
    created_at timestamp(6) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    work_order_id uuid NOT NULL
);


--
-- Name: work_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_orders (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    number character varying NOT NULL,
    title character varying NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    origin character varying NOT NULL,
    priority character varying DEFAULT 'normal'::character varying NOT NULL,
    customer_id uuid NOT NULL,
    service_location_id uuid NOT NULL,
    problem_description text NOT NULL,
    diagnosis text,
    solution text,
    requested_at timestamp(6) with time zone NOT NULL,
    started_at timestamp(6) with time zone,
    completed_at timestamp(6) with time zone,
    canceled_at timestamp(6) with time zone,
    cancel_reason text,
    reopened_count integer DEFAULT 0 NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    quote_version_id uuid,
    service_type_id uuid,
    created_by_membership_id uuid,
    contract_id uuid,
    requested_by_contact_id uuid,
    CONSTRAINT work_orders_author CHECK (((created_by_membership_id IS NOT NULL) OR (requested_by_contact_id IS NOT NULL))),
    CONSTRAINT work_orders_cancel_reason CHECK ((((status)::text <> 'canceled'::text) OR ((canceled_at IS NOT NULL) AND (cancel_reason IS NOT NULL)))),
    CONSTRAINT work_orders_completed_at CHECK ((((status)::text <> 'completed'::text) OR (completed_at IS NOT NULL))),
    CONSTRAINT work_orders_origin CHECK (((origin)::text = ANY (ARRAY['phone'::text, 'email'::text, 'whatsapp'::text, 'portal'::text, 'quote'::text, 'preventive'::text, 'internal'::text]))),
    CONSTRAINT work_orders_priority CHECK (((priority)::text = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
    CONSTRAINT work_orders_status CHECK (((status)::text = ANY (ARRAY['open'::text, 'awaiting_approval'::text, 'approved'::text, 'scheduled'::text, 'in_progress'::text, 'waiting_parts'::text, 'waiting_customer'::text, 'completed'::text, 'reopened'::text, 'canceled'::text])))
);


--
-- Name: work_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_schedules (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    weekday integer NOT NULL,
    start_minute integer NOT NULL,
    end_minute integer NOT NULL,
    created_at timestamp(6) with time zone NOT NULL,
    updated_at timestamp(6) with time zone NOT NULL,
    membership_id uuid NOT NULL,
    CONSTRAINT work_schedules_interval CHECK (((start_minute >= 0) AND (end_minute <= 1440) AND (start_minute < end_minute))),
    CONSTRAINT work_schedules_weekday CHECK (((weekday >= 0) AND (weekday <= 6)))
);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: api_credentials api_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_credentials
    ADD CONSTRAINT api_credentials_pkey PRIMARY KEY (id);


--
-- Name: api_idempotency_keys api_idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_idempotency_keys
    ADD CONSTRAINT api_idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: business_hours business_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours
    ADD CONSTRAINT business_hours_pkey PRIMARY KEY (id);


--
-- Name: catalog_items catalog_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_items
    ADD CONSTRAINT catalog_items_pkey PRIMARY KEY (id);


--
-- Name: contract_service_types contract_service_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_service_types
    ADD CONSTRAINT contract_service_types_pkey PRIMARY KEY (id);


--
-- Name: contract_versions contract_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_versions
    ADD CONSTRAINT contract_versions_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: customer_contacts customer_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT customer_contacts_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: equipment_events equipment_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment_events
    ADD CONSTRAINT equipment_events_pkey PRIMARY KEY (id);


--
-- Name: equipment equipment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment
    ADD CONSTRAINT equipment_pkey PRIMARY KEY (id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: field_operations field_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_operations
    ADD CONSTRAINT field_operations_pkey PRIMARY KEY (id);


--
-- Name: financial_events financial_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_events
    ADD CONSTRAINT financial_events_pkey PRIMARY KEY (id);


--
-- Name: holidays holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holidays
    ADD CONSTRAINT holidays_pkey PRIMARY KEY (id);


--
-- Name: inbound_webhooks inbound_webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_webhooks
    ADD CONSTRAINT inbound_webhooks_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: maintenance_occurrences maintenance_occurrences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_occurrences
    ADD CONSTRAINT maintenance_occurrences_pkey PRIMARY KEY (id);


--
-- Name: maintenance_plan_equipment maintenance_plan_equipment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plan_equipment
    ADD CONSTRAINT maintenance_plan_equipment_pkey PRIMARY KEY (id);


--
-- Name: maintenance_plans maintenance_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT maintenance_plans_pkey PRIMARY KEY (id);


--
-- Name: material_consumptions material_consumptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT material_consumptions_pkey PRIMARY KEY (id);


--
-- Name: membership_skills membership_skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_skills
    ADD CONSTRAINT membership_skills_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: organization_counters organization_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_counters
    ADD CONSTRAINT organization_counters_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: outbox_event_failures outbox_event_failures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_event_failures
    ADD CONSTRAINT outbox_event_failures_pkey PRIMARY KEY (id);


--
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (id);


--
-- Name: payment_charges payment_charges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_charges
    ADD CONSTRAINT payment_charges_pkey PRIMARY KEY (id);


--
-- Name: payment_integrations payment_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_integrations
    ADD CONSTRAINT payment_integrations_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: plan_modules plan_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_modules
    ADD CONSTRAINT plan_modules_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: portal_access_grants portal_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_access_grants
    ADD CONSTRAINT portal_access_grants_pkey PRIMARY KEY (id);


--
-- Name: portal_sessions portal_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_sessions
    ADD CONSTRAINT portal_sessions_pkey PRIMARY KEY (id);


--
-- Name: quote_events quote_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_events
    ADD CONSTRAINT quote_events_pkey PRIMARY KEY (id);


--
-- Name: quote_items quote_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT quote_items_pkey PRIMARY KEY (id);


--
-- Name: quote_versions quote_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_versions
    ADD CONSTRAINT quote_versions_pkey PRIMARY KEY (id);


--
-- Name: quotes quotes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT quotes_pkey PRIMARY KEY (id);


--
-- Name: receivables receivables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT receivables_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: service_locations service_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT service_locations_pkey PRIMARY KEY (id);


--
-- Name: service_type_checklist_items service_type_checklist_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_checklist_items
    ADD CONSTRAINT service_type_checklist_items_pkey PRIMARY KEY (id);


--
-- Name: service_type_skills service_type_skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_skills
    ADD CONSTRAINT service_type_skills_pkey PRIMARY KEY (id);


--
-- Name: service_types service_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_types
    ADD CONSTRAINT service_types_pkey PRIMARY KEY (id);


--
-- Name: skills skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skills
    ADD CONSTRAINT skills_pkey PRIMARY KEY (id);


--
-- Name: sla_clock_events sla_clock_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_clock_events
    ADD CONSTRAINT sla_clock_events_pkey PRIMARY KEY (id);


--
-- Name: sla_clocks sla_clocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_clocks
    ADD CONSTRAINT sla_clocks_pkey PRIMARY KEY (id);


--
-- Name: sla_policies sla_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_policies
    ADD CONSTRAINT sla_policies_pkey PRIMARY KEY (id);


--
-- Name: stock_balances stock_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_balances
    ADD CONSTRAINT stock_balances_pkey PRIMARY KEY (id);


--
-- Name: stock_movements stock_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id);


--
-- Name: stock_reservations stock_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_pkey PRIMARY KEY (id);


--
-- Name: subscription_invoices subscription_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_invoices
    ADD CONSTRAINT subscription_invoices_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: technician_allocations technician_allocations_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_allocations
    ADD CONSTRAINT technician_allocations_no_overlap EXCLUDE USING gist (organization_id WITH =, membership_id WITH =, period WITH &&) WHERE (((status)::text = 'active'::text));


--
-- Name: technician_allocations technician_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_allocations
    ADD CONSTRAINT technician_allocations_pkey PRIMARY KEY (id);


--
-- Name: time_entries time_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT time_entries_pkey PRIMARY KEY (id);


--
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: visit_transitions visit_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visit_transitions
    ADD CONSTRAINT visit_transitions_pkey PRIMARY KEY (id);


--
-- Name: visits visits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visits
    ADD CONSTRAINT visits_pkey PRIMARY KEY (id);


--
-- Name: warehouses warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_pkey PRIMARY KEY (id);


--
-- Name: webhook_deliveries webhook_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deliveries
    ADD CONSTRAINT webhook_deliveries_pkey PRIMARY KEY (id);


--
-- Name: webhook_endpoints webhook_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_pkey PRIMARY KEY (id);


--
-- Name: work_order_assignments work_order_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_assignments
    ADD CONSTRAINT work_order_assignments_pkey PRIMARY KEY (id);


--
-- Name: work_order_checklist_items work_order_checklist_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_checklist_items
    ADD CONSTRAINT work_order_checklist_items_pkey PRIMARY KEY (id);


--
-- Name: work_order_equipment work_order_equipment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_equipment
    ADD CONSTRAINT work_order_equipment_pkey PRIMARY KEY (id);


--
-- Name: work_order_evidences work_order_evidences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_evidences
    ADD CONSTRAINT work_order_evidences_pkey PRIMARY KEY (id);


--
-- Name: work_order_items work_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_items
    ADD CONSTRAINT work_order_items_pkey PRIMARY KEY (id);


--
-- Name: work_order_reports work_order_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_reports
    ADD CONSTRAINT work_order_reports_pkey PRIMARY KEY (id);


--
-- Name: work_order_transitions work_order_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_transitions
    ADD CONSTRAINT work_order_transitions_pkey PRIMARY KEY (id);


--
-- Name: work_orders work_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT work_orders_pkey PRIMARY KEY (id);


--
-- Name: work_schedules work_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_pkey PRIMARY KEY (id);


--
-- Name: idx_on_contract_id_service_type_id_4f53b748d2; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_contract_id_service_type_id_4f53b748d2 ON public.contract_service_types USING btree (contract_id, service_type_id);


--
-- Name: idx_on_organization_id_auditable_type_auditable_id_b2857e335c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_auditable_type_auditable_id_b2857e335c ON public.audit_events USING btree (organization_id, auditable_type, auditable_id);


--
-- Name: idx_on_organization_id_custodian_membership_id_bc36378208; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_custodian_membership_id_bc36378208 ON public.warehouses USING btree (organization_id, custodian_membership_id);


--
-- Name: idx_on_organization_id_equipment_id_occurred_at_c8e2c7ae7c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_equipment_id_occurred_at_c8e2c7ae7c ON public.equipment_events USING btree (organization_id, equipment_id, occurred_at);


--
-- Name: idx_on_organization_id_external_reference_564cb051a0; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_organization_id_external_reference_564cb051a0 ON public.payment_charges USING btree (organization_id, external_reference);


--
-- Name: idx_on_organization_id_external_reference_5f228312af; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_organization_id_external_reference_5f228312af ON public.subscription_invoices USING btree (organization_id, external_reference);


--
-- Name: idx_on_organization_id_invited_by_membership_id_24eab2f90c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_invited_by_membership_id_24eab2f90c ON public.invitations USING btree (organization_id, invited_by_membership_id);


--
-- Name: idx_on_organization_id_kind_active_name_677c9f430a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_kind_active_name_677c9f430a ON public.catalog_items USING btree (organization_id, kind, active, name);


--
-- Name: idx_on_organization_id_membership_id_765e54b84e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_membership_id_765e54b84e ON public.work_order_assignments USING btree (organization_id, membership_id);


--
-- Name: idx_on_organization_id_outbox_event_id_4fefddfda1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_outbox_event_id_4fefddfda1 ON public.outbox_event_failures USING btree (organization_id, outbox_event_id);


--
-- Name: idx_on_organization_id_service_type_id_0173a78480; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_service_type_id_0173a78480 ON public.contract_service_types USING btree (organization_id, service_type_id);


--
-- Name: idx_on_organization_id_service_type_id_db08157b19; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_service_type_id_db08157b19 ON public.service_type_checklist_items USING btree (organization_id, service_type_id);


--
-- Name: idx_on_organization_id_status_created_at_1118c31bba; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_status_created_at_1118c31bba ON public.outbox_events USING btree (organization_id, status, created_at);


--
-- Name: idx_on_organization_id_status_created_at_7c7e187d71; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_status_created_at_7c7e187d71 ON public.webhook_deliveries USING btree (organization_id, status, created_at);


--
-- Name: idx_on_organization_id_status_due_on_a1d7524e32; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_status_due_on_a1d7524e32 ON public.subscription_invoices USING btree (organization_id, status, due_on);


--
-- Name: idx_on_organization_id_status_priority_requested_at_20346fbe18; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_status_priority_requested_at_20346fbe18 ON public.work_orders USING btree (organization_id, status, priority, requested_at);


--
-- Name: idx_on_organization_id_weekday_start_minute_ae5523c8b9; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_organization_id_weekday_start_minute_ae5523c8b9 ON public.business_hours USING btree (organization_id, weekday, start_minute);


--
-- Name: idx_on_organization_id_work_order_id_074bd6e1b0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_work_order_id_074bd6e1b0 ON public.material_consumptions USING btree (organization_id, work_order_id);


--
-- Name: idx_on_organization_id_work_order_id_1445d5d793; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_work_order_id_1445d5d793 ON public.work_order_evidences USING btree (organization_id, work_order_id);


--
-- Name: idx_on_organization_id_work_order_id_5a82199b7e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_work_order_id_5a82199b7e ON public.work_order_equipment USING btree (organization_id, work_order_id);


--
-- Name: idx_on_organization_id_work_order_id_8b9dd6799b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_work_order_id_8b9dd6799b ON public.work_order_transitions USING btree (organization_id, work_order_id);


--
-- Name: idx_on_organization_id_work_order_id_abfa99dc1a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_work_order_id_abfa99dc1a ON public.work_order_checklist_items USING btree (organization_id, work_order_id);


--
-- Name: idx_on_subscription_id_period_start_806596f228; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_subscription_id_period_start_806596f228 ON public.subscription_invoices USING btree (subscription_id, period_start);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_blobs_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_tenant_key ON public.active_storage_blobs USING btree (organization_id, id);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_allocations_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_allocations_lookup ON public.technician_allocations USING btree (organization_id, membership_id, status);


--
-- Name: index_api_credentials_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_credentials_on_tenant_key ON public.api_credentials USING btree (organization_id, id);


--
-- Name: index_api_credentials_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_credentials_on_token_digest ON public.api_credentials USING btree (token_digest);


--
-- Name: index_api_idempotency_keys_on_api_credential_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_idempotency_keys_on_api_credential_id_and_key ON public.api_idempotency_keys USING btree (api_credential_id, key);


--
-- Name: index_api_idempotency_keys_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_idempotency_keys_on_tenant_key ON public.api_idempotency_keys USING btree (organization_id, id);


--
-- Name: index_assignments_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assignments_unique ON public.work_order_assignments USING btree (organization_id, work_order_id, membership_id);


--
-- Name: index_audit_events_on_organization_id_and_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_organization_id_and_action ON public.audit_events USING btree (organization_id, action);


--
-- Name: index_audit_events_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_organization_id_and_created_at ON public.audit_events USING btree (organization_id, created_at DESC);


--
-- Name: index_audit_events_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_events_on_tenant_key ON public.audit_events USING btree (organization_id, id);


--
-- Name: index_business_hours_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_business_hours_on_tenant_key ON public.business_hours USING btree (organization_id, id);


--
-- Name: index_catalog_items_on_organization_id_and_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_items_on_organization_id_and_sku ON public.catalog_items USING btree (organization_id, sku) WHERE (sku IS NOT NULL);


--
-- Name: index_catalog_items_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_items_on_tenant_key ON public.catalog_items USING btree (organization_id, id);


--
-- Name: index_contract_service_types_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_service_types_on_tenant_key ON public.contract_service_types USING btree (organization_id, id);


--
-- Name: index_contract_versions_on_contract_id_and_version_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_versions_on_contract_id_and_version_number ON public.contract_versions USING btree (contract_id, version_number);


--
-- Name: index_contract_versions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_versions_on_tenant_key ON public.contract_versions USING btree (organization_id, id);


--
-- Name: index_contracts_on_customer_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_customer_key ON public.contracts USING btree (organization_id, customer_id, id);


--
-- Name: index_contracts_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_organization_id_and_customer_id ON public.contracts USING btree (organization_id, customer_id);


--
-- Name: index_contracts_on_organization_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_organization_id_and_number ON public.contracts USING btree (organization_id, number);


--
-- Name: index_contracts_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_tenant_key ON public.contracts USING btree (organization_id, id);


--
-- Name: index_customer_contacts_on_customer_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customer_contacts_on_customer_key ON public.customer_contacts USING btree (organization_id, customer_id, id);


--
-- Name: index_customer_contacts_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_contacts_on_organization_id_and_customer_id ON public.customer_contacts USING btree (organization_id, customer_id);


--
-- Name: index_customer_contacts_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customer_contacts_on_tenant_key ON public.customer_contacts USING btree (organization_id, id);


--
-- Name: index_customers_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_name_trgm ON public.customers USING gin (name public.gin_trgm_ops);


--
-- Name: index_customers_on_organization_id_and_archived_at_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_organization_id_and_archived_at_and_name ON public.customers USING btree (organization_id, archived_at, name);


--
-- Name: index_customers_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_tenant_key ON public.customers USING btree (organization_id, id);


--
-- Name: index_customers_unique_document; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_unique_document ON public.customers USING btree (organization_id, document) WHERE (document IS NOT NULL);


--
-- Name: index_equipment_events_on_organization_id_and_equipment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_equipment_events_on_organization_id_and_equipment_id ON public.equipment_events USING btree (organization_id, equipment_id);


--
-- Name: index_equipment_events_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equipment_events_on_tenant_key ON public.equipment_events USING btree (organization_id, id);


--
-- Name: index_equipment_on_customer_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equipment_on_customer_key ON public.equipment USING btree (organization_id, customer_id, id);


--
-- Name: index_equipment_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_equipment_on_organization_id_and_customer_id ON public.equipment USING btree (organization_id, customer_id);


--
-- Name: index_equipment_on_organization_id_and_service_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_equipment_on_organization_id_and_service_location_id ON public.equipment USING btree (organization_id, service_location_id);


--
-- Name: index_equipment_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equipment_on_tenant_key ON public.equipment USING btree (organization_id, id);


--
-- Name: index_equipment_unique_asset_tag; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equipment_unique_asset_tag ON public.equipment USING btree (organization_id, asset_tag) WHERE (asset_tag IS NOT NULL);


--
-- Name: index_equipment_unique_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_equipment_unique_serial ON public.equipment USING btree (organization_id, manufacturer, serial_number) WHERE (serial_number IS NOT NULL);


--
-- Name: index_expenses_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_expenses_on_organization_id_and_work_order_id ON public.expenses USING btree (organization_id, work_order_id);


--
-- Name: index_expenses_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_expenses_on_tenant_key ON public.expenses USING btree (organization_id, id);


--
-- Name: index_field_operations_on_organization_id_and_operation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_field_operations_on_organization_id_and_operation_id ON public.field_operations USING btree (organization_id, operation_id);


--
-- Name: index_field_operations_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_field_operations_on_organization_id_and_work_order_id ON public.field_operations USING btree (organization_id, work_order_id);


--
-- Name: index_field_operations_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_field_operations_on_tenant_key ON public.field_operations USING btree (organization_id, id);


--
-- Name: index_financial_events_on_organization_id_and_receivable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_financial_events_on_organization_id_and_receivable_id ON public.financial_events USING btree (organization_id, receivable_id);


--
-- Name: index_financial_events_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_financial_events_on_tenant_key ON public.financial_events USING btree (organization_id, id);


--
-- Name: index_holidays_on_organization_id_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_holidays_on_organization_id_and_date ON public.holidays USING btree (organization_id, date);


--
-- Name: index_holidays_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_holidays_on_tenant_key ON public.holidays USING btree (organization_id, id);


--
-- Name: index_inbound_webhooks_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_webhooks_dedup ON public.inbound_webhooks USING btree (organization_id, provider, external_event_id);


--
-- Name: index_inbound_webhooks_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_webhooks_on_tenant_key ON public.inbound_webhooks USING btree (organization_id, id);


--
-- Name: index_invitations_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_tenant_key ON public.invitations USING btree (organization_id, id);


--
-- Name: index_invitations_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token_digest ON public.invitations USING btree (token_digest);


--
-- Name: index_invitations_pending_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_pending_email ON public.invitations USING btree (organization_id, email) WHERE ((accepted_at IS NULL) AND (revoked_at IS NULL));


--
-- Name: index_maintenance_occurrences_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_maintenance_occurrences_identity ON public.maintenance_occurrences USING btree (maintenance_plan_id, sequence);


--
-- Name: index_maintenance_occurrences_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_maintenance_occurrences_on_tenant_key ON public.maintenance_occurrences USING btree (organization_id, id);


--
-- Name: index_maintenance_occurrences_on_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_maintenance_occurrences_on_work_order_id ON public.maintenance_occurrences USING btree (work_order_id);


--
-- Name: index_maintenance_plan_equipment_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_maintenance_plan_equipment_on_tenant_key ON public.maintenance_plan_equipment USING btree (organization_id, id);


--
-- Name: index_maintenance_plan_equipment_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_maintenance_plan_equipment_unique ON public.maintenance_plan_equipment USING btree (maintenance_plan_id, equipment_id);


--
-- Name: index_maintenance_plans_on_organization_id_and_contract_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_plans_on_organization_id_and_contract_id ON public.maintenance_plans USING btree (organization_id, contract_id);


--
-- Name: index_maintenance_plans_on_organization_id_and_service_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_maintenance_plans_on_organization_id_and_service_type_id ON public.maintenance_plans USING btree (organization_id, service_type_id);


--
-- Name: index_maintenance_plans_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_maintenance_plans_on_tenant_key ON public.maintenance_plans USING btree (organization_id, id);


--
-- Name: index_material_consumptions_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_material_consumptions_idempotency ON public.material_consumptions USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_material_consumptions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_material_consumptions_on_tenant_key ON public.material_consumptions USING btree (organization_id, id);


--
-- Name: index_membership_skills_on_organization_id_and_skill_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_membership_skills_on_organization_id_and_skill_id ON public.membership_skills USING btree (organization_id, skill_id);


--
-- Name: index_membership_skills_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_membership_skills_on_tenant_key ON public.membership_skills USING btree (organization_id, id);


--
-- Name: index_membership_skills_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_membership_skills_unique ON public.membership_skills USING btree (organization_id, membership_id, skill_id);


--
-- Name: index_memberships_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_organization_id_and_user_id ON public.memberships USING btree (organization_id, user_id);


--
-- Name: index_memberships_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_tenant_key ON public.memberships USING btree (organization_id, id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_notifications_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notifications_dedup ON public.notifications USING btree (organization_id, outbox_event_id, recipient_membership_id, kind);


--
-- Name: index_notifications_inbox; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_inbox ON public.notifications USING btree (organization_id, recipient_membership_id, created_at DESC);


--
-- Name: index_notifications_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notifications_on_tenant_key ON public.notifications USING btree (organization_id, id);


--
-- Name: index_organization_counters_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organization_counters_key ON public.organization_counters USING btree (organization_id, scope, year);


--
-- Name: index_organization_counters_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organization_counters_on_tenant_key ON public.organization_counters USING btree (organization_id, id);


--
-- Name: index_outbox_event_failures_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_outbox_event_failures_on_tenant_key ON public.outbox_event_failures USING btree (organization_id, id);


--
-- Name: index_outbox_events_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_due ON public.outbox_events USING btree (available_at, id) WHERE ((status)::text = 'pending'::text);


--
-- Name: index_outbox_events_leases; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_leases ON public.outbox_events USING btree (locked_until) WHERE ((status)::text = 'processing'::text);


--
-- Name: index_outbox_events_on_organization_id_and_dedup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_outbox_events_on_organization_id_and_dedup_key ON public.outbox_events USING btree (organization_id, dedup_key) WHERE (dedup_key IS NOT NULL);


--
-- Name: index_outbox_events_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_outbox_events_on_tenant_key ON public.outbox_events USING btree (organization_id, id);


--
-- Name: index_payment_charges_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_charges_external_id ON public.payment_charges USING btree (organization_id, provider, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_payment_charges_on_organization_id_and_receivable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_charges_on_organization_id_and_receivable_id ON public.payment_charges USING btree (organization_id, receivable_id);


--
-- Name: index_payment_charges_on_status_and_last_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_charges_on_status_and_last_synced_at ON public.payment_charges USING btree (status, last_synced_at);


--
-- Name: index_payment_charges_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_charges_on_tenant_key ON public.payment_charges USING btree (organization_id, id);


--
-- Name: index_payment_charges_single_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_charges_single_active ON public.payment_charges USING btree (receivable_id) WHERE ((status)::text = ANY (ARRAY['pending'::text, 'submitted'::text, 'unknown'::text]));


--
-- Name: index_payment_integrations_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_integrations_on_tenant_key ON public.payment_integrations USING btree (organization_id, id);


--
-- Name: index_payment_integrations_on_webhook_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_integrations_on_webhook_token_digest ON public.payment_integrations USING btree (webhook_token_digest) WHERE (webhook_token_digest IS NOT NULL);


--
-- Name: index_payment_integrations_single; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_integrations_single ON public.payment_integrations USING btree (organization_id);


--
-- Name: index_payments_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payments_idempotency ON public.payments USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_payments_on_organization_id_and_payment_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_organization_id_and_payment_charge_id ON public.payments USING btree (organization_id, payment_charge_id);


--
-- Name: index_payments_on_organization_id_and_receivable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_organization_id_and_receivable_id ON public.payments USING btree (organization_id, receivable_id);


--
-- Name: index_payments_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payments_on_tenant_key ON public.payments USING btree (organization_id, id);


--
-- Name: index_plan_modules_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plan_modules_on_code ON public.plan_modules USING btree (code);


--
-- Name: index_plans_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_code ON public.plans USING btree (code);


--
-- Name: index_portal_access_grants_on_organization_id_and_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_access_grants_on_organization_id_and_contact_id ON public.portal_access_grants USING btree (organization_id, contact_id);


--
-- Name: index_portal_access_grants_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_access_grants_on_tenant_key ON public.portal_access_grants USING btree (organization_id, id);


--
-- Name: index_portal_access_grants_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_access_grants_on_token_digest ON public.portal_access_grants USING btree (token_digest);


--
-- Name: index_portal_grants_per_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_grants_per_event ON public.portal_access_grants USING btree (organization_id, outbox_event_id, contact_id) WHERE (outbox_event_id IS NOT NULL);


--
-- Name: index_portal_sessions_on_organization_id_and_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_sessions_on_organization_id_and_contact_id ON public.portal_sessions USING btree (organization_id, contact_id);


--
-- Name: index_portal_sessions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_sessions_on_tenant_key ON public.portal_sessions USING btree (organization_id, id);


--
-- Name: index_portal_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_sessions_on_token_digest ON public.portal_sessions USING btree (token_digest);


--
-- Name: index_quote_events_on_organization_id_and_quote_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quote_events_on_organization_id_and_quote_id ON public.quote_events USING btree (organization_id, quote_id);


--
-- Name: index_quote_events_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quote_events_on_tenant_key ON public.quote_events USING btree (organization_id, id);


--
-- Name: index_quote_items_on_organization_id_and_catalog_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quote_items_on_organization_id_and_catalog_item_id ON public.quote_items USING btree (organization_id, catalog_item_id);


--
-- Name: index_quote_items_on_organization_id_and_quote_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quote_items_on_organization_id_and_quote_version_id ON public.quote_items USING btree (organization_id, quote_version_id);


--
-- Name: index_quote_items_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quote_items_on_tenant_key ON public.quote_items USING btree (organization_id, id);


--
-- Name: index_quote_versions_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quote_versions_number ON public.quote_versions USING btree (organization_id, quote_id, version_number);


--
-- Name: index_quote_versions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quote_versions_on_tenant_key ON public.quote_versions USING btree (organization_id, id);


--
-- Name: index_quotes_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quotes_on_organization_id_and_customer_id ON public.quotes USING btree (organization_id, customer_id);


--
-- Name: index_quotes_on_organization_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quotes_on_organization_id_and_number ON public.quotes USING btree (organization_id, number);


--
-- Name: index_quotes_on_organization_id_and_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quotes_on_organization_id_and_status_and_created_at ON public.quotes USING btree (organization_id, status, created_at);


--
-- Name: index_quotes_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quotes_on_tenant_key ON public.quotes USING btree (organization_id, id);


--
-- Name: index_receivables_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_organization_id_and_customer_id ON public.receivables USING btree (organization_id, customer_id);


--
-- Name: index_receivables_on_organization_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_receivables_on_organization_id_and_number ON public.receivables USING btree (organization_id, number);


--
-- Name: index_receivables_on_organization_id_and_status_and_due_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_organization_id_and_status_and_due_on ON public.receivables USING btree (organization_id, status, due_on);


--
-- Name: index_receivables_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_receivables_on_organization_id_and_work_order_id ON public.receivables USING btree (organization_id, work_order_id);


--
-- Name: index_receivables_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_receivables_on_tenant_key ON public.receivables USING btree (organization_id, id);


--
-- Name: index_service_locations_on_customer_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_locations_on_customer_key ON public.service_locations USING btree (organization_id, customer_id, id);


--
-- Name: index_service_locations_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_locations_on_organization_id_and_customer_id ON public.service_locations USING btree (organization_id, customer_id);


--
-- Name: index_service_locations_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_locations_on_tenant_key ON public.service_locations USING btree (organization_id, id);


--
-- Name: index_service_type_checklist_items_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_type_checklist_items_on_tenant_key ON public.service_type_checklist_items USING btree (organization_id, id);


--
-- Name: index_service_type_skills_on_organization_id_and_skill_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_type_skills_on_organization_id_and_skill_id ON public.service_type_skills USING btree (organization_id, skill_id);


--
-- Name: index_service_type_skills_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_type_skills_on_tenant_key ON public.service_type_skills USING btree (organization_id, id);


--
-- Name: index_service_type_skills_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_type_skills_unique ON public.service_type_skills USING btree (organization_id, service_type_id, skill_id);


--
-- Name: index_service_types_on_organization_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_types_on_organization_id_and_name ON public.service_types USING btree (organization_id, name);


--
-- Name: index_service_types_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_types_on_tenant_key ON public.service_types USING btree (organization_id, id);


--
-- Name: index_skills_on_organization_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_skills_on_organization_id_and_name ON public.skills USING btree (organization_id, name);


--
-- Name: index_skills_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_skills_on_tenant_key ON public.skills USING btree (organization_id, id);


--
-- Name: index_sla_clock_events_on_organization_id_and_sla_clock_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sla_clock_events_on_organization_id_and_sla_clock_id ON public.sla_clock_events USING btree (organization_id, sla_clock_id);


--
-- Name: index_sla_clock_events_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sla_clock_events_on_tenant_key ON public.sla_clock_events USING btree (organization_id, id);


--
-- Name: index_sla_clocks_on_organization_id_and_status_and_due_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sla_clocks_on_organization_id_and_status_and_due_at ON public.sla_clocks USING btree (organization_id, status, due_at);


--
-- Name: index_sla_clocks_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sla_clocks_on_tenant_key ON public.sla_clocks USING btree (organization_id, id);


--
-- Name: index_sla_clocks_on_work_order_id_and_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sla_clocks_on_work_order_id_and_metric ON public.sla_clocks USING btree (work_order_id, metric);


--
-- Name: index_sla_policies_on_organization_id_and_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sla_policies_on_organization_id_and_priority ON public.sla_policies USING btree (organization_id, priority);


--
-- Name: index_sla_policies_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sla_policies_on_tenant_key ON public.sla_policies USING btree (organization_id, id);


--
-- Name: index_stock_balances_on_organization_id_and_catalog_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_balances_on_organization_id_and_catalog_item_id ON public.stock_balances USING btree (organization_id, catalog_item_id);


--
-- Name: index_stock_balances_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_balances_on_tenant_key ON public.stock_balances USING btree (organization_id, id);


--
-- Name: index_stock_balances_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_balances_unique ON public.stock_balances USING btree (organization_id, warehouse_id, catalog_item_id);


--
-- Name: index_stock_movements_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_history ON public.stock_movements USING btree (organization_id, warehouse_id, catalog_item_id, occurred_at);


--
-- Name: index_stock_movements_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_movements_idempotency ON public.stock_movements USING btree (organization_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_stock_movements_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_movements_on_organization_id_and_work_order_id ON public.stock_movements USING btree (organization_id, work_order_id);


--
-- Name: index_stock_movements_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_movements_on_tenant_key ON public.stock_movements USING btree (organization_id, id);


--
-- Name: index_stock_reservations_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stock_reservations_on_organization_id_and_work_order_id ON public.stock_reservations USING btree (organization_id, work_order_id);


--
-- Name: index_stock_reservations_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stock_reservations_on_tenant_key ON public.stock_reservations USING btree (organization_id, id);


--
-- Name: index_subscription_invoices_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subscription_invoices_on_tenant_key ON public.subscription_invoices USING btree (organization_id, id);


--
-- Name: index_subscriptions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subscriptions_on_tenant_key ON public.subscriptions USING btree (organization_id, id);


--
-- Name: index_subscriptions_one_per_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subscriptions_one_per_organization ON public.subscriptions USING btree (organization_id);


--
-- Name: index_team_members_on_organization_id_and_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_members_on_organization_id_and_membership_id ON public.team_members USING btree (organization_id, membership_id);


--
-- Name: index_team_members_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_members_on_tenant_key ON public.team_members USING btree (organization_id, id);


--
-- Name: index_team_members_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_members_unique ON public.team_members USING btree (organization_id, team_id, membership_id);


--
-- Name: index_teams_on_organization_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_organization_id_and_name ON public.teams USING btree (organization_id, name);


--
-- Name: index_teams_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_tenant_key ON public.teams USING btree (organization_id, id);


--
-- Name: index_technician_allocations_on_organization_id_and_visit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_allocations_on_organization_id_and_visit_id ON public.technician_allocations USING btree (organization_id, visit_id);


--
-- Name: index_technician_allocations_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_technician_allocations_on_tenant_key ON public.technician_allocations USING btree (organization_id, id);


--
-- Name: index_time_entries_on_organization_id_and_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_organization_id_and_membership_id ON public.time_entries USING btree (organization_id, membership_id);


--
-- Name: index_time_entries_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_organization_id_and_work_order_id ON public.time_entries USING btree (organization_id, work_order_id);


--
-- Name: index_time_entries_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_time_entries_on_tenant_key ON public.time_entries USING btree (organization_id, id);


--
-- Name: index_time_entries_operation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_time_entries_operation ON public.time_entries USING btree (organization_id, client_operation_id) WHERE (client_operation_id IS NOT NULL);


--
-- Name: index_user_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_sessions_on_user_id ON public.user_sessions USING btree (user_id);


--
-- Name: index_user_sessions_on_user_id_and_revoked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_sessions_on_user_id_and_revoked_at ON public.user_sessions USING btree (user_id, revoked_at);


--
-- Name: index_users_on_confirmation_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_confirmation_token ON public.users USING btree (confirmation_token);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_unlock_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_unlock_token ON public.users USING btree (unlock_token);


--
-- Name: index_visit_transitions_on_organization_id_and_visit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_visit_transitions_on_organization_id_and_visit_id ON public.visit_transitions USING btree (organization_id, visit_id);


--
-- Name: index_visit_transitions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_visit_transitions_on_tenant_key ON public.visit_transitions USING btree (organization_id, id);


--
-- Name: index_visits_on_organization_id_and_status_and_scheduled_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_visits_on_organization_id_and_status_and_scheduled_start ON public.visits USING btree (organization_id, status, scheduled_start);


--
-- Name: index_visits_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_visits_on_organization_id_and_work_order_id ON public.visits USING btree (organization_id, work_order_id);


--
-- Name: index_visits_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_visits_on_tenant_key ON public.visits USING btree (organization_id, id);


--
-- Name: index_warehouses_on_organization_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_warehouses_on_organization_id_and_name ON public.warehouses USING btree (organization_id, name);


--
-- Name: index_warehouses_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_warehouses_on_tenant_key ON public.warehouses USING btree (organization_id, id);


--
-- Name: index_webhook_deliveries_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webhook_deliveries_on_tenant_key ON public.webhook_deliveries USING btree (organization_id, id);


--
-- Name: index_webhook_deliveries_on_webhook_endpoint_id_and_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webhook_deliveries_on_webhook_endpoint_id_and_event_id ON public.webhook_deliveries USING btree (webhook_endpoint_id, event_id);


--
-- Name: index_webhook_endpoints_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webhook_endpoints_on_tenant_key ON public.webhook_endpoints USING btree (organization_id, id);


--
-- Name: index_work_order_assignments_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_assignments_on_tenant_key ON public.work_order_assignments USING btree (organization_id, id);


--
-- Name: index_work_order_checklist_items_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_checklist_items_on_tenant_key ON public.work_order_checklist_items USING btree (organization_id, id);


--
-- Name: index_work_order_equipment_on_organization_id_and_equipment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_order_equipment_on_organization_id_and_equipment_id ON public.work_order_equipment USING btree (organization_id, equipment_id);


--
-- Name: index_work_order_equipment_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_equipment_on_tenant_key ON public.work_order_equipment USING btree (organization_id, id);


--
-- Name: index_work_order_equipment_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_equipment_unique ON public.work_order_equipment USING btree (organization_id, work_order_id, equipment_id);


--
-- Name: index_work_order_evidences_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_evidences_on_tenant_key ON public.work_order_evidences USING btree (organization_id, id);


--
-- Name: index_work_order_items_on_organization_id_and_work_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_order_items_on_organization_id_and_work_order_id ON public.work_order_items USING btree (organization_id, work_order_id);


--
-- Name: index_work_order_items_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_items_on_tenant_key ON public.work_order_items USING btree (organization_id, id);


--
-- Name: index_work_order_reports_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_reports_on_tenant_key ON public.work_order_reports USING btree (organization_id, id);


--
-- Name: index_work_order_reports_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_reports_version ON public.work_order_reports USING btree (organization_id, work_order_id, version_number);


--
-- Name: index_work_order_transitions_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_order_transitions_on_tenant_key ON public.work_order_transitions USING btree (organization_id, id);


--
-- Name: index_work_orders_on_contract_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_orders_on_contract_usage ON public.work_orders USING btree (organization_id, contract_id, requested_at);


--
-- Name: index_work_orders_on_customer_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_orders_on_customer_key ON public.work_orders USING btree (organization_id, id, customer_id);


--
-- Name: index_work_orders_on_organization_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_orders_on_organization_id_and_customer_id ON public.work_orders USING btree (organization_id, customer_id);


--
-- Name: index_work_orders_on_organization_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_orders_on_organization_id_and_number ON public.work_orders USING btree (organization_id, number);


--
-- Name: index_work_orders_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_orders_on_tenant_key ON public.work_orders USING btree (organization_id, id);


--
-- Name: index_work_orders_one_per_quote_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_orders_one_per_quote_version ON public.work_orders USING btree (organization_id, quote_version_id) WHERE (quote_version_id IS NOT NULL);


--
-- Name: index_work_schedules_on_organization_id_and_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_schedules_on_organization_id_and_membership_id ON public.work_schedules USING btree (organization_id, membership_id);


--
-- Name: index_work_schedules_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_work_schedules_on_tenant_key ON public.work_schedules USING btree (organization_id, id);


--
-- Name: quote_items quote_items_frozen; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER quote_items_frozen BEFORE INSERT OR DELETE OR UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION public.servora_guard_frozen_quote_items();


--
-- Name: quote_versions quote_versions_frozen; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER quote_versions_frozen BEFORE UPDATE ON public.quote_versions FOR EACH ROW EXECUTE FUNCTION public.servora_guard_frozen_quote_versions();


--
-- Name: quote_versions quote_versions_no_delete_after_draft; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER quote_versions_no_delete_after_draft BEFORE DELETE ON public.quote_versions FOR EACH ROW WHEN (((old.status)::text <> 'draft'::text)) EXECUTE FUNCTION public.servora_forbid_sent_quote_version_delete();


--
-- Name: stock_balances stock_balances_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stock_balances_guard BEFORE INSERT OR UPDATE ON public.stock_balances FOR EACH ROW EXECUTE FUNCTION public.servora_guard_stock_balance();


--
-- Name: active_storage_attachments fk_active_storage_attachments_blob_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_active_storage_attachments_blob_tenant FOREIGN KEY (organization_id, blob_id) REFERENCES public.active_storage_blobs(organization_id, id);


--
-- Name: active_storage_variant_records fk_active_storage_variant_records_blob_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_active_storage_variant_records_blob_tenant FOREIGN KEY (organization_id, blob_id) REFERENCES public.active_storage_blobs(organization_id, id);


--
-- Name: api_credentials fk_api_credentials_created_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_credentials
    ADD CONSTRAINT fk_api_credentials_created_by_membership_id_tenant FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: api_idempotency_keys fk_api_idempotency_keys_api_credential_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_idempotency_keys
    ADD CONSTRAINT fk_api_idempotency_keys_api_credential_id_tenant FOREIGN KEY (organization_id, api_credential_id) REFERENCES public.api_credentials(organization_id, id);


--
-- Name: contract_service_types fk_contract_service_types_contract_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_service_types
    ADD CONSTRAINT fk_contract_service_types_contract_id_tenant FOREIGN KEY (organization_id, contract_id) REFERENCES public.contracts(organization_id, id);


--
-- Name: contract_service_types fk_contract_service_types_service_type_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_service_types
    ADD CONSTRAINT fk_contract_service_types_service_type_id_tenant FOREIGN KEY (organization_id, service_type_id) REFERENCES public.service_types(organization_id, id);


--
-- Name: contract_versions fk_contract_versions_contract_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_versions
    ADD CONSTRAINT fk_contract_versions_contract_id_tenant FOREIGN KEY (organization_id, contract_id) REFERENCES public.contracts(organization_id, id);


--
-- Name: contracts fk_contracts_created_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_contracts_created_by_membership_id_tenant FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: contracts fk_contracts_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_contracts_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: customer_contacts fk_customer_contacts_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT fk_customer_contacts_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: equipment fk_equipment_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment
    ADD CONSTRAINT fk_equipment_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: equipment_events fk_equipment_events_equipment_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment_events
    ADD CONSTRAINT fk_equipment_events_equipment_id_tenant FOREIGN KEY (organization_id, equipment_id) REFERENCES public.equipment(organization_id, id) ON DELETE CASCADE;


--
-- Name: equipment fk_equipment_location_of_same_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment
    ADD CONSTRAINT fk_equipment_location_of_same_customer FOREIGN KEY (organization_id, customer_id, service_location_id) REFERENCES public.service_locations(organization_id, customer_id, id);


--
-- Name: expenses fk_expenses_recorded_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_expenses_recorded_by_membership_id_tenant FOREIGN KEY (organization_id, recorded_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: expenses fk_expenses_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_expenses_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: field_operations fk_field_operations_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_operations
    ADD CONSTRAINT fk_field_operations_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: field_operations fk_field_operations_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_operations
    ADD CONSTRAINT fk_field_operations_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: financial_events fk_financial_events_payment_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_events
    ADD CONSTRAINT fk_financial_events_payment_id_tenant FOREIGN KEY (organization_id, payment_id) REFERENCES public.payments(organization_id, id);


--
-- Name: financial_events fk_financial_events_receivable_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_events
    ADD CONSTRAINT fk_financial_events_receivable_id_tenant FOREIGN KEY (organization_id, receivable_id) REFERENCES public.receivables(organization_id, id);


--
-- Name: invitations fk_invitations_invited_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_invitations_invited_by_membership_id_tenant FOREIGN KEY (organization_id, invited_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: maintenance_occurrences fk_maintenance_occurrences_maintenance_plan_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_occurrences
    ADD CONSTRAINT fk_maintenance_occurrences_maintenance_plan_id_tenant FOREIGN KEY (organization_id, maintenance_plan_id) REFERENCES public.maintenance_plans(organization_id, id);


--
-- Name: maintenance_occurrences fk_maintenance_occurrences_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_occurrences
    ADD CONSTRAINT fk_maintenance_occurrences_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: maintenance_plan_equipment fk_maintenance_plan_equipment_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plan_equipment
    ADD CONSTRAINT fk_maintenance_plan_equipment_customer FOREIGN KEY (organization_id, customer_id, equipment_id) REFERENCES public.equipment(organization_id, customer_id, id);


--
-- Name: maintenance_plan_equipment fk_maintenance_plan_equipment_maintenance_plan_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plan_equipment
    ADD CONSTRAINT fk_maintenance_plan_equipment_maintenance_plan_id_tenant FOREIGN KEY (organization_id, maintenance_plan_id) REFERENCES public.maintenance_plans(organization_id, id);


--
-- Name: maintenance_plans fk_maintenance_plans_contract_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_contract_customer FOREIGN KEY (organization_id, customer_id, contract_id) REFERENCES public.contracts(organization_id, customer_id, id);


--
-- Name: maintenance_plans fk_maintenance_plans_contract_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_contract_id_tenant FOREIGN KEY (organization_id, contract_id) REFERENCES public.contracts(organization_id, id);


--
-- Name: maintenance_plans fk_maintenance_plans_created_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_created_by_membership_id_tenant FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: maintenance_plans fk_maintenance_plans_location_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_location_customer FOREIGN KEY (organization_id, customer_id, service_location_id) REFERENCES public.service_locations(organization_id, customer_id, id);


--
-- Name: maintenance_plans fk_maintenance_plans_service_type_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_maintenance_plans_service_type_id_tenant FOREIGN KEY (organization_id, service_type_id) REFERENCES public.service_types(organization_id, id);


--
-- Name: material_consumptions fk_material_consumptions_catalog_item_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT fk_material_consumptions_catalog_item_id_tenant FOREIGN KEY (organization_id, catalog_item_id) REFERENCES public.catalog_items(organization_id, id);


--
-- Name: material_consumptions fk_material_consumptions_movement_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT fk_material_consumptions_movement_id_tenant FOREIGN KEY (organization_id, movement_id) REFERENCES public.stock_movements(organization_id, id);


--
-- Name: material_consumptions fk_material_consumptions_reservation_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT fk_material_consumptions_reservation_id_tenant FOREIGN KEY (organization_id, reservation_id) REFERENCES public.stock_reservations(organization_id, id);


--
-- Name: material_consumptions fk_material_consumptions_warehouse_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT fk_material_consumptions_warehouse_id_tenant FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.warehouses(organization_id, id);


--
-- Name: material_consumptions fk_material_consumptions_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT fk_material_consumptions_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: membership_skills fk_membership_skills_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_skills
    ADD CONSTRAINT fk_membership_skills_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id) ON DELETE CASCADE;


--
-- Name: membership_skills fk_membership_skills_skill_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_skills
    ADD CONSTRAINT fk_membership_skills_skill_id_tenant FOREIGN KEY (organization_id, skill_id) REFERENCES public.skills(organization_id, id) ON DELETE CASCADE;


--
-- Name: notifications fk_notifications_recipient_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_notifications_recipient_membership_id_tenant FOREIGN KEY (organization_id, recipient_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: outbox_event_failures fk_outbox_event_failures_outbox_event_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_event_failures
    ADD CONSTRAINT fk_outbox_event_failures_outbox_event_id_tenant FOREIGN KEY (organization_id, outbox_event_id) REFERENCES public.outbox_events(organization_id, id);


--
-- Name: payment_charges fk_payment_charges_receivable_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_charges
    ADD CONSTRAINT fk_payment_charges_receivable_id_tenant FOREIGN KEY (organization_id, receivable_id) REFERENCES public.receivables(organization_id, id);


--
-- Name: payments fk_payments_payment_charge_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_payment_charge_id_tenant FOREIGN KEY (organization_id, payment_charge_id) REFERENCES public.payment_charges(organization_id, id);


--
-- Name: payments fk_payments_receivable_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_receivable_id_tenant FOREIGN KEY (organization_id, receivable_id) REFERENCES public.receivables(organization_id, id);


--
-- Name: payments fk_payments_recorded_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_payments_recorded_by_membership_id_tenant FOREIGN KEY (organization_id, recorded_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: portal_access_grants fk_portal_access_grants_contact_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_access_grants
    ADD CONSTRAINT fk_portal_access_grants_contact_id_tenant FOREIGN KEY (organization_id, contact_id) REFERENCES public.customer_contacts(organization_id, id);


--
-- Name: portal_access_grants fk_portal_access_grants_quote_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_access_grants
    ADD CONSTRAINT fk_portal_access_grants_quote_id_tenant FOREIGN KEY (organization_id, quote_id) REFERENCES public.quotes(organization_id, id);


--
-- Name: portal_sessions fk_portal_sessions_contact_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_sessions
    ADD CONSTRAINT fk_portal_sessions_contact_id_tenant FOREIGN KEY (organization_id, contact_id) REFERENCES public.customer_contacts(organization_id, id);


--
-- Name: portal_sessions fk_portal_sessions_grant_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_sessions
    ADD CONSTRAINT fk_portal_sessions_grant_id_tenant FOREIGN KEY (organization_id, grant_id) REFERENCES public.portal_access_grants(organization_id, id);


--
-- Name: quote_events fk_quote_events_quote_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_events
    ADD CONSTRAINT fk_quote_events_quote_id_tenant FOREIGN KEY (organization_id, quote_id) REFERENCES public.quotes(organization_id, id);


--
-- Name: quote_events fk_quote_events_quote_version_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_events
    ADD CONSTRAINT fk_quote_events_quote_version_id_tenant FOREIGN KEY (organization_id, quote_version_id) REFERENCES public.quote_versions(organization_id, id);


--
-- Name: quote_items fk_quote_items_catalog_item_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT fk_quote_items_catalog_item_id_tenant FOREIGN KEY (organization_id, catalog_item_id) REFERENCES public.catalog_items(organization_id, id);


--
-- Name: quote_items fk_quote_items_quote_version_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT fk_quote_items_quote_version_id_tenant FOREIGN KEY (organization_id, quote_version_id) REFERENCES public.quote_versions(organization_id, id) ON DELETE CASCADE;


--
-- Name: quote_versions fk_quote_versions_decided_by_contact_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_versions
    ADD CONSTRAINT fk_quote_versions_decided_by_contact_id_tenant FOREIGN KEY (organization_id, decided_by_contact_id) REFERENCES public.customer_contacts(organization_id, id);


--
-- Name: quote_versions fk_quote_versions_decided_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_versions
    ADD CONSTRAINT fk_quote_versions_decided_by_membership_id_tenant FOREIGN KEY (organization_id, decided_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: quote_versions fk_quote_versions_quote_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_versions
    ADD CONSTRAINT fk_quote_versions_quote_id_tenant FOREIGN KEY (organization_id, quote_id) REFERENCES public.quotes(organization_id, id);


--
-- Name: quotes fk_quotes_approved_version_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_quotes_approved_version_id_tenant FOREIGN KEY (organization_id, approved_version_id) REFERENCES public.quote_versions(organization_id, id);


--
-- Name: quotes fk_quotes_created_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_quotes_created_by_membership_id_tenant FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: quotes fk_quotes_current_version_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_quotes_current_version_id_tenant FOREIGN KEY (organization_id, current_version_id) REFERENCES public.quote_versions(organization_id, id);


--
-- Name: quotes fk_quotes_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_quotes_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: quotes fk_quotes_location_of_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_quotes_location_of_customer FOREIGN KEY (organization_id, customer_id, service_location_id) REFERENCES public.service_locations(organization_id, customer_id, id);


--
-- Name: material_consumptions fk_rails_000009b795; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_consumptions
    ADD CONSTRAINT fk_rails_000009b795 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: organization_counters fk_rails_02bad7a88a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_counters
    ADD CONSTRAINT fk_rails_02bad7a88a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: stock_movements fk_rails_081f669265; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_rails_081f669265 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_items fk_rails_084e8e77d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_items
    ADD CONSTRAINT fk_rails_084e8e77d0 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: invitations fk_rails_0fe4c14f0e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_0fe4c14f0e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: service_type_skills fk_rails_11c672af69; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_skills
    ADD CONSTRAINT fk_rails_11c672af69 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: visit_transitions fk_rails_19b8aa9e8e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visit_transitions
    ADD CONSTRAINT fk_rails_19b8aa9e8e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: holidays fk_rails_1afd2ce622; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holidays
    ADD CONSTRAINT fk_rails_1afd2ce622 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_assignments fk_rails_1b8a8a53ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_assignments
    ADD CONSTRAINT fk_rails_1b8a8a53ac FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: webhook_endpoints fk_rails_21808fa528; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT fk_rails_21808fa528 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: maintenance_plan_equipment fk_rails_22cbc11974; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plan_equipment
    ADD CONSTRAINT fk_rails_22cbc11974 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: maintenance_plans fk_rails_249b0e4599; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_plans
    ADD CONSTRAINT fk_rails_249b0e4599 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payment_charges fk_rails_2b518ebdf9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_charges
    ADD CONSTRAINT fk_rails_2b518ebdf9 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: field_operations fk_rails_2e5c7f5ca2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.field_operations
    ADD CONSTRAINT fk_rails_2e5c7f5ca2 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: service_locations fk_rails_2f359873f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT fk_rails_2f359873f8 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: stock_balances fk_rails_3415eb8782; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_balances
    ADD CONSTRAINT fk_rails_3415eb8782 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: business_hours fk_rails_35acd7f354; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours
    ADD CONSTRAINT fk_rails_35acd7f354 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: subscriptions fk_rails_364213cc3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_364213cc3e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: inbound_webhooks fk_rails_36cda06530; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_webhooks
    ADD CONSTRAINT fk_rails_36cda06530 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: financial_events fk_rails_376b99903d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_events
    ADD CONSTRAINT fk_rails_376b99903d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: notifications fk_rails_394d9847aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_394d9847aa FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: service_type_checklist_items fk_rails_3a0232caa8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_checklist_items
    ADD CONSTRAINT fk_rails_3a0232caa8 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payments fk_rails_3ab959bfc4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_rails_3ab959bfc4 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: warehouses fk_rails_4792852b95; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT fk_rails_4792852b95 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: sla_clocks fk_rails_492295a44f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_clocks
    ADD CONSTRAINT fk_rails_492295a44f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_reports fk_rails_4b371782c8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_reports
    ADD CONSTRAINT fk_rails_4b371782c8 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_orders fk_rails_4ec807c8ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_rails_4ec807c8ae FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: active_storage_attachments fk_rails_51dbd6101d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_51dbd6101d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: equipment fk_rails_5284aaf58e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment
    ADD CONSTRAINT fk_rails_5284aaf58e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: customers fk_rails_58234c715e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_58234c715e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: sla_clock_events fk_rails_58f85684b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_clock_events
    ADD CONSTRAINT fk_rails_58f85684b0 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: active_storage_blobs fk_rails_5946a08084; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT fk_rails_5946a08084 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: contract_service_types fk_rails_5cd6448630; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_service_types
    ADD CONSTRAINT fk_rails_5cd6448630 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: subscription_invoices fk_rails_5d152dcc3c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_invoices
    ADD CONSTRAINT fk_rails_5d152dcc3c FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: subscriptions fk_rails_63d3df128b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_63d3df128b FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: memberships fk_rails_64267aab58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_64267aab58 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: expenses fk_rails_69a027cec6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_rails_69a027cec6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: portal_sessions fk_rails_6c5460f6fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_sessions
    ADD CONSTRAINT fk_rails_6c5460f6fc FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: quote_items fk_rails_6cfe192463; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT fk_rails_6cfe192463 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: visits fk_rails_6efda2cfb2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visits
    ADD CONSTRAINT fk_rails_6efda2cfb2 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: membership_skills fk_rails_6f0cf5e81b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_skills
    ADD CONSTRAINT fk_rails_6f0cf5e81b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: time_entries fk_rails_6fa304b886; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_6fa304b886 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: portal_access_grants fk_rails_721b04c463; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_access_grants
    ADD CONSTRAINT fk_rails_721b04c463 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: sla_policies fk_rails_7f66676233; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_policies
    ADD CONSTRAINT fk_rails_7f66676233 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_transitions fk_rails_8030aa2bf5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_transitions
    ADD CONSTRAINT fk_rails_8030aa2bf5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_checklist_items fk_rails_87fc4ab3dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_checklist_items
    ADD CONSTRAINT fk_rails_87fc4ab3dc FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: stock_reservations fk_rails_918e762877; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT fk_rails_918e762877 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: outbox_event_failures fk_rails_93d0f08c9e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_event_failures
    ADD CONSTRAINT fk_rails_93d0f08c9e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: team_members fk_rails_99fbd57ee0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT fk_rails_99fbd57ee0 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: maintenance_occurrences fk_rails_9e9a70410b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maintenance_occurrences
    ADD CONSTRAINT fk_rails_9e9a70410b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: user_sessions fk_rails_9fa262d742; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT fk_rails_9fa262d742 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: contracts fk_rails_a48f7202cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_a48f7202cc FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: technician_allocations fk_rails_a8356d52fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_allocations
    ADD CONSTRAINT fk_rails_a8356d52fc FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: quote_events fk_rails_b3e599d683; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_events
    ADD CONSTRAINT fk_rails_b3e599d683 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: receivables fk_rails_b43dab699d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_rails_b43dab699d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: outbox_events fk_rails_b6cb24ddb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT fk_rails_b6cb24ddb3 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payment_integrations fk_rails_b9b437da45; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_integrations
    ADD CONSTRAINT fk_rails_b9b437da45 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: invitations fk_rails_bbf4c77a36; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_bbf4c77a36 FOREIGN KEY (accepted_user_id) REFERENCES public.users(id);


--
-- Name: audit_events fk_rails_be0ed9e37f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_rails_be0ed9e37f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: api_credentials fk_rails_be4b4015d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_credentials
    ADD CONSTRAINT fk_rails_be4b4015d9 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: skills fk_rails_befcd0faff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skills
    ADD CONSTRAINT fk_rails_befcd0faff FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: customer_contacts fk_rails_c2c8ebb3b1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT fk_rails_c2c8ebb3b1 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_evidences fk_rails_c407c1ab9a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_evidences
    ADD CONSTRAINT fk_rails_c407c1ab9a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_schedules fk_rails_cd24788784; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT fk_rails_cd24788784 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: work_order_equipment fk_rails_cd24dbaf4f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_equipment
    ADD CONSTRAINT fk_rails_cd24dbaf4f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: quote_versions fk_rails_d2d917b73a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_versions
    ADD CONSTRAINT fk_rails_d2d917b73a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: catalog_items fk_rails_d72295177d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_items
    ADD CONSTRAINT fk_rails_d72295177d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: contract_versions fk_rails_d7d5b6fcc4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_versions
    ADD CONSTRAINT fk_rails_d7d5b6fcc4 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: quotes fk_rails_de7694c307; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_rails_de7694c307 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: equipment_events fk_rails_e71dc665bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipment_events
    ADD CONSTRAINT fk_rails_e71dc665bc FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: active_storage_variant_records fk_rails_e89407238a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_e89407238a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: webhook_deliveries fk_rails_ea5a0897ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deliveries
    ADD CONSTRAINT fk_rails_ea5a0897ac FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: service_types fk_rails_eeff69bade; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_types
    ADD CONSTRAINT fk_rails_eeff69bade FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: teams fk_rails_f07f0bd66d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_f07f0bd66d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: api_idempotency_keys fk_rails_fc344f108a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_idempotency_keys
    ADD CONSTRAINT fk_rails_fc344f108a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: receivables fk_receivables_created_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_receivables_created_by_membership_id_tenant FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: receivables fk_receivables_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_receivables_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: receivables fk_receivables_work_order_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_receivables_work_order_customer FOREIGN KEY (organization_id, work_order_id, customer_id) REFERENCES public.work_orders(organization_id, id, customer_id);


--
-- Name: receivables fk_receivables_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receivables
    ADD CONSTRAINT fk_receivables_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: service_locations fk_service_locations_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT fk_service_locations_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: service_type_checklist_items fk_service_type_checklist_items_service_type_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_checklist_items
    ADD CONSTRAINT fk_service_type_checklist_items_service_type_id_tenant FOREIGN KEY (organization_id, service_type_id) REFERENCES public.service_types(organization_id, id) ON DELETE CASCADE;


--
-- Name: service_type_skills fk_service_type_skills_service_type_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_skills
    ADD CONSTRAINT fk_service_type_skills_service_type_id_tenant FOREIGN KEY (organization_id, service_type_id) REFERENCES public.service_types(organization_id, id) ON DELETE CASCADE;


--
-- Name: service_type_skills fk_service_type_skills_skill_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_type_skills
    ADD CONSTRAINT fk_service_type_skills_skill_id_tenant FOREIGN KEY (organization_id, skill_id) REFERENCES public.skills(organization_id, id) ON DELETE CASCADE;


--
-- Name: sla_clock_events fk_sla_clock_events_sla_clock_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_clock_events
    ADD CONSTRAINT fk_sla_clock_events_sla_clock_id_tenant FOREIGN KEY (organization_id, sla_clock_id) REFERENCES public.sla_clocks(organization_id, id);


--
-- Name: sla_clocks fk_sla_clocks_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_clocks
    ADD CONSTRAINT fk_sla_clocks_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: stock_balances fk_stock_balances_catalog_item_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_balances
    ADD CONSTRAINT fk_stock_balances_catalog_item_id_tenant FOREIGN KEY (organization_id, catalog_item_id) REFERENCES public.catalog_items(organization_id, id);


--
-- Name: stock_balances fk_stock_balances_last_movement_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_balances
    ADD CONSTRAINT fk_stock_balances_last_movement_id_tenant FOREIGN KEY (organization_id, last_movement_id) REFERENCES public.stock_movements(organization_id, id);


--
-- Name: stock_balances fk_stock_balances_warehouse_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_balances
    ADD CONSTRAINT fk_stock_balances_warehouse_id_tenant FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.warehouses(organization_id, id);


--
-- Name: stock_movements fk_stock_movements_catalog_item_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_stock_movements_catalog_item_id_tenant FOREIGN KEY (organization_id, catalog_item_id) REFERENCES public.catalog_items(organization_id, id);


--
-- Name: stock_movements fk_stock_movements_warehouse_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_stock_movements_warehouse_id_tenant FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.warehouses(organization_id, id);


--
-- Name: stock_movements fk_stock_movements_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movements
    ADD CONSTRAINT fk_stock_movements_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: stock_reservations fk_stock_reservations_catalog_item_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT fk_stock_reservations_catalog_item_id_tenant FOREIGN KEY (organization_id, catalog_item_id) REFERENCES public.catalog_items(organization_id, id);


--
-- Name: stock_reservations fk_stock_reservations_warehouse_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT fk_stock_reservations_warehouse_id_tenant FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.warehouses(organization_id, id);


--
-- Name: stock_reservations fk_stock_reservations_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT fk_stock_reservations_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: subscription_invoices fk_subscription_invoices_subscription_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_invoices
    ADD CONSTRAINT fk_subscription_invoices_subscription_id_tenant FOREIGN KEY (organization_id, subscription_id) REFERENCES public.subscriptions(organization_id, id);


--
-- Name: team_members fk_team_members_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT fk_team_members_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id) ON DELETE CASCADE;


--
-- Name: team_members fk_team_members_team_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT fk_team_members_team_id_tenant FOREIGN KEY (organization_id, team_id) REFERENCES public.teams(organization_id, id) ON DELETE CASCADE;


--
-- Name: technician_allocations fk_technician_allocations_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_allocations
    ADD CONSTRAINT fk_technician_allocations_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: technician_allocations fk_technician_allocations_visit_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_allocations
    ADD CONSTRAINT fk_technician_allocations_visit_id_tenant FOREIGN KEY (organization_id, visit_id) REFERENCES public.visits(organization_id, id);


--
-- Name: time_entries fk_time_entries_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_time_entries_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: time_entries fk_time_entries_visit_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_time_entries_visit_id_tenant FOREIGN KEY (organization_id, visit_id) REFERENCES public.visits(organization_id, id);


--
-- Name: time_entries fk_time_entries_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_time_entries_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: visit_transitions fk_visit_transitions_visit_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visit_transitions
    ADD CONSTRAINT fk_visit_transitions_visit_id_tenant FOREIGN KEY (organization_id, visit_id) REFERENCES public.visits(organization_id, id);


--
-- Name: visits fk_visits_scheduled_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visits
    ADD CONSTRAINT fk_visits_scheduled_by_membership_id_tenant FOREIGN KEY (organization_id, scheduled_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: visits fk_visits_team_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visits
    ADD CONSTRAINT fk_visits_team_id_tenant FOREIGN KEY (organization_id, team_id) REFERENCES public.teams(organization_id, id);


--
-- Name: visits fk_visits_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.visits
    ADD CONSTRAINT fk_visits_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: warehouses fk_warehouses_custodian_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT fk_warehouses_custodian_membership_id_tenant FOREIGN KEY (organization_id, custodian_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: webhook_deliveries fk_webhook_deliveries_webhook_endpoint_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deliveries
    ADD CONSTRAINT fk_webhook_deliveries_webhook_endpoint_id_tenant FOREIGN KEY (organization_id, webhook_endpoint_id) REFERENCES public.webhook_endpoints(organization_id, id);


--
-- Name: work_order_assignments fk_work_order_assignments_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_assignments
    ADD CONSTRAINT fk_work_order_assignments_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: work_order_assignments fk_work_order_assignments_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_assignments
    ADD CONSTRAINT fk_work_order_assignments_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id) ON DELETE CASCADE;


--
-- Name: work_order_checklist_items fk_work_order_checklist_items_responded_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_checklist_items
    ADD CONSTRAINT fk_work_order_checklist_items_responded_by_membership_id_tenant FOREIGN KEY (organization_id, responded_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: work_order_checklist_items fk_work_order_checklist_items_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_checklist_items
    ADD CONSTRAINT fk_work_order_checklist_items_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id) ON DELETE CASCADE;


--
-- Name: work_order_equipment fk_work_order_equipment_of_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_equipment
    ADD CONSTRAINT fk_work_order_equipment_of_customer FOREIGN KEY (organization_id, customer_id, equipment_id) REFERENCES public.equipment(organization_id, customer_id, id);


--
-- Name: work_order_equipment fk_work_order_equipment_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_equipment
    ADD CONSTRAINT fk_work_order_equipment_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id) ON DELETE CASCADE;


--
-- Name: work_order_evidences fk_work_order_evidences_uploaded_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_evidences
    ADD CONSTRAINT fk_work_order_evidences_uploaded_by_membership_id_tenant FOREIGN KEY (organization_id, uploaded_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: work_order_evidences fk_work_order_evidences_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_evidences
    ADD CONSTRAINT fk_work_order_evidences_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: work_order_items fk_work_order_items_authorized_by_contact_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_items
    ADD CONSTRAINT fk_work_order_items_authorized_by_contact_id_tenant FOREIGN KEY (organization_id, authorized_by_contact_id) REFERENCES public.customer_contacts(organization_id, id);


--
-- Name: work_order_items fk_work_order_items_authorized_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_items
    ADD CONSTRAINT fk_work_order_items_authorized_by_membership_id_tenant FOREIGN KEY (organization_id, authorized_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: work_order_items fk_work_order_items_catalog_item_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_items
    ADD CONSTRAINT fk_work_order_items_catalog_item_id_tenant FOREIGN KEY (organization_id, catalog_item_id) REFERENCES public.catalog_items(organization_id, id);


--
-- Name: work_order_items fk_work_order_items_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_items
    ADD CONSTRAINT fk_work_order_items_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: work_order_reports fk_work_order_reports_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_reports
    ADD CONSTRAINT fk_work_order_reports_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: work_order_transitions fk_work_order_transitions_work_order_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_order_transitions
    ADD CONSTRAINT fk_work_order_transitions_work_order_id_tenant FOREIGN KEY (organization_id, work_order_id) REFERENCES public.work_orders(organization_id, id);


--
-- Name: work_orders fk_work_orders_contract_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_contract_customer FOREIGN KEY (organization_id, customer_id, contract_id) REFERENCES public.contracts(organization_id, customer_id, id);


--
-- Name: work_orders fk_work_orders_created_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_created_by_membership_id_tenant FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES public.memberships(organization_id, id);


--
-- Name: work_orders fk_work_orders_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: work_orders fk_work_orders_location_of_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_location_of_customer FOREIGN KEY (organization_id, customer_id, service_location_id) REFERENCES public.service_locations(organization_id, customer_id, id);


--
-- Name: work_orders fk_work_orders_quote_version_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_quote_version_id_tenant FOREIGN KEY (organization_id, quote_version_id) REFERENCES public.quote_versions(organization_id, id);


--
-- Name: work_orders fk_work_orders_requested_by_contact; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_requested_by_contact FOREIGN KEY (organization_id, customer_id, requested_by_contact_id) REFERENCES public.customer_contacts(organization_id, customer_id, id);


--
-- Name: work_orders fk_work_orders_service_type_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_orders
    ADD CONSTRAINT fk_work_orders_service_type_id_tenant FOREIGN KEY (organization_id, service_type_id) REFERENCES public.service_types(organization_id, id);


--
-- Name: work_schedules fk_work_schedules_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT fk_work_schedules_membership_id_tenant FOREIGN KEY (organization_id, membership_id) REFERENCES public.memberships(organization_id, id) ON DELETE CASCADE;


--
-- Name: active_storage_attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.active_storage_attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: active_storage_blobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.active_storage_blobs ENABLE ROW LEVEL SECURITY;

--
-- Name: active_storage_variant_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.active_storage_variant_records ENABLE ROW LEVEL SECURITY;

--
-- Name: api_credentials; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.api_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: api_idempotency_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.api_idempotency_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

--
-- Name: business_hours; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.business_hours ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_service_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_service_types ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: contracts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- Name: equipment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.equipment ENABLE ROW LEVEL SECURITY;

--
-- Name: equipment_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.equipment_events ENABLE ROW LEVEL SECURITY;

--
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- Name: field_operations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.field_operations ENABLE ROW LEVEL SECURITY;

--
-- Name: financial_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.financial_events ENABLE ROW LEVEL SECURITY;

--
-- Name: holidays; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

--
-- Name: inbound_webhooks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inbound_webhooks ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: maintenance_occurrences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_occurrences ENABLE ROW LEVEL SECURITY;

--
-- Name: maintenance_plan_equipment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_plan_equipment ENABLE ROW LEVEL SECURITY;

--
-- Name: maintenance_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.maintenance_plans ENABLE ROW LEVEL SECURITY;

--
-- Name: material_consumptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.material_consumptions ENABLE ROW LEVEL SECURITY;

--
-- Name: membership_skills; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.membership_skills ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships memberships_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_insert ON public.memberships FOR INSERT WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: memberships memberships_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_select ON public.memberships FOR SELECT USING (((organization_id = public.servora_current_organization_id()) OR (user_id = public.servora_current_user_id())));


--
-- Name: memberships memberships_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_update ON public.memberships FOR UPDATE USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: organization_counters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organization_counters ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations organizations_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_insert ON public.organizations FOR INSERT WITH CHECK ((id = public.servora_current_organization_id()));


--
-- Name: organizations organizations_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_select ON public.organizations FOR SELECT USING (((id = public.servora_current_organization_id()) OR (EXISTS ( SELECT 1
   FROM public.memberships m
  WHERE ((m.organization_id = organizations.id) AND (m.user_id = public.servora_current_user_id()) AND ((m.status)::text = 'active'::text))))));


--
-- Name: organizations organizations_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY organizations_update ON public.organizations FOR UPDATE USING ((id = public.servora_current_organization_id())) WITH CHECK ((id = public.servora_current_organization_id()));


--
-- Name: outbox_event_failures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.outbox_event_failures ENABLE ROW LEVEL SECURITY;

--
-- Name: outbox_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_charges; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_charges ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_integrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_integrations ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: portal_access_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.portal_access_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: portal_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.portal_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: quote_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quote_events ENABLE ROW LEVEL SECURITY;

--
-- Name: quote_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quote_items ENABLE ROW LEVEL SECURITY;

--
-- Name: quote_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quote_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: quotes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

--
-- Name: receivables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.receivables ENABLE ROW LEVEL SECURITY;

--
-- Name: service_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: service_type_checklist_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_type_checklist_items ENABLE ROW LEVEL SECURITY;

--
-- Name: service_type_skills; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_type_skills ENABLE ROW LEVEL SECURITY;

--
-- Name: service_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_types ENABLE ROW LEVEL SECURITY;

--
-- Name: skills; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.skills ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_clock_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sla_clock_events ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_clocks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sla_clocks ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sla_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_balances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_balances ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_reservations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_reservations ENABLE ROW LEVEL SECURITY;

--
-- Name: subscription_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscription_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: team_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;

--
-- Name: teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

--
-- Name: technician_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.technician_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: active_storage_attachments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.active_storage_attachments USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: active_storage_blobs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.active_storage_blobs USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: active_storage_variant_records tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.active_storage_variant_records USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: api_credentials tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.api_credentials USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: api_idempotency_keys tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.api_idempotency_keys USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: audit_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: business_hours tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.business_hours USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: catalog_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.catalog_items USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: contract_service_types tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.contract_service_types USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: contract_versions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.contract_versions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: contracts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.contracts USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: customer_contacts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customer_contacts USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: customers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customers USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: equipment tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.equipment USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: equipment_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.equipment_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: expenses tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.expenses USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: field_operations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.field_operations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: financial_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.financial_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: holidays tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.holidays USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: inbound_webhooks tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.inbound_webhooks USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: invitations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invitations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: maintenance_occurrences tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.maintenance_occurrences USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: maintenance_plan_equipment tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.maintenance_plan_equipment USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: maintenance_plans tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.maintenance_plans USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: material_consumptions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.material_consumptions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: membership_skills tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.membership_skills USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: notifications tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.notifications USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: organization_counters tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.organization_counters USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: outbox_event_failures tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.outbox_event_failures USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: outbox_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.outbox_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: payment_charges tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payment_charges USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: payment_integrations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payment_integrations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: payments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payments USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: portal_access_grants tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.portal_access_grants USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: portal_sessions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.portal_sessions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: quote_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.quote_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: quote_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.quote_items USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: quote_versions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.quote_versions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: quotes tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.quotes USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: receivables tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.receivables USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: service_locations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_locations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: service_type_checklist_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_type_checklist_items USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: service_type_skills tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_type_skills USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: service_types tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_types USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: skills tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.skills USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: sla_clock_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sla_clock_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: sla_clocks tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sla_clocks USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: sla_policies tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sla_policies USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: stock_balances tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.stock_balances USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: stock_movements tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.stock_movements USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: stock_reservations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.stock_reservations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: subscription_invoices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.subscription_invoices USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: subscriptions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.subscriptions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: team_members tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.team_members USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: teams tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.teams USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: technician_allocations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.technician_allocations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: time_entries tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.time_entries USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: visit_transitions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.visit_transitions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: visits tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.visits USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: warehouses tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.warehouses USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: webhook_deliveries tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.webhook_deliveries USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: webhook_endpoints tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.webhook_endpoints USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_assignments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_assignments USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_checklist_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_checklist_items USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_equipment tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_equipment USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_evidences tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_evidences USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_items USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_reports tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_reports USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_order_transitions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_order_transitions USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_orders tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_orders USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: work_schedules tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.work_schedules USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: time_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.time_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: visit_transitions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.visit_transitions ENABLE ROW LEVEL SECURITY;

--
-- Name: visits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;

--
-- Name: warehouses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.warehouses ENABLE ROW LEVEL SECURITY;

--
-- Name: webhook_deliveries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;

--
-- Name: webhook_endpoints; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.webhook_endpoints ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_checklist_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_checklist_items ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_equipment; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_equipment ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_evidences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_evidences ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_reports ENABLE ROW LEVEL SECURITY;

--
-- Name: work_order_transitions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_order_transitions ENABLE ROW LEVEL SECURITY;

--
-- Name: work_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: work_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_schedules ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261125030000'),
('20261124015000'),
('20261124014000'),
('20261124013000'),
('20261124012000'),
('20261124011000'),
('20261124010000'),
('20261124009000'),
('20261124008000'),
('20261124007000'),
('20261124006100'),
('20261124006000'),
('20261124005100'),
('20261124005000'),
('20261124004300'),
('20261124004200'),
('20261124004100'),
('20261124004000'),
('20261124003100'),
('20261124003000'),
('20261124002100'),
('20261124002000'),
('20261124001300'),
('20261124001200'),
('20261124001100'),
('20261124001000'),
('20261124000100');

