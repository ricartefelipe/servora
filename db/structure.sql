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
-- Name: servora_resolve_invitation(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.servora_resolve_invitation(p_token_digest text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ SELECT organization_id FROM invitations WHERE token_digest = p_token_digest $$;


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
-- Name: catalog_items catalog_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_items
    ADD CONSTRAINT catalog_items_pkey PRIMARY KEY (id);


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
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


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
-- Name: idx_on_organization_id_auditable_type_auditable_id_b2857e335c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_auditable_type_auditable_id_b2857e335c ON public.audit_events USING btree (organization_id, auditable_type, auditable_id);


--
-- Name: idx_on_organization_id_equipment_id_occurred_at_c8e2c7ae7c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_equipment_id_occurred_at_c8e2c7ae7c ON public.equipment_events USING btree (organization_id, equipment_id, occurred_at);


--
-- Name: idx_on_organization_id_invited_by_membership_id_24eab2f90c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_invited_by_membership_id_24eab2f90c ON public.invitations USING btree (organization_id, invited_by_membership_id);


--
-- Name: idx_on_organization_id_kind_active_name_677c9f430a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_kind_active_name_677c9f430a ON public.catalog_items USING btree (organization_id, kind, active, name);


--
-- Name: idx_on_organization_id_outbox_event_id_4fefddfda1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_outbox_event_id_4fefddfda1 ON public.outbox_event_failures USING btree (organization_id, outbox_event_id);


--
-- Name: idx_on_organization_id_status_created_at_1118c31bba; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_status_created_at_1118c31bba ON public.outbox_events USING btree (organization_id, status, created_at);


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
-- Name: index_catalog_items_on_organization_id_and_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_items_on_organization_id_and_sku ON public.catalog_items USING btree (organization_id, sku) WHERE (sku IS NOT NULL);


--
-- Name: index_catalog_items_on_tenant_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_items_on_tenant_key ON public.catalog_items USING btree (organization_id, id);


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
-- Name: invitations fk_invitations_invited_by_membership_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_invitations_invited_by_membership_id_tenant FOREIGN KEY (organization_id, invited_by_membership_id) REFERENCES public.memberships(organization_id, id);


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
-- Name: organization_counters fk_rails_02bad7a88a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_counters
    ADD CONSTRAINT fk_rails_02bad7a88a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: invitations fk_rails_0fe4c14f0e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_0fe4c14f0e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: service_locations fk_rails_2f359873f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT fk_rails_2f359873f8 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: notifications fk_rails_394d9847aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_394d9847aa FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: memberships fk_rails_64267aab58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_64267aab58 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: portal_access_grants fk_rails_721b04c463; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_access_grants
    ADD CONSTRAINT fk_rails_721b04c463 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: user_sessions fk_rails_9fa262d742; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT fk_rails_9fa262d742 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: quote_events fk_rails_b3e599d683; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_events
    ADD CONSTRAINT fk_rails_b3e599d683 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: outbox_events fk_rails_b6cb24ddb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT fk_rails_b6cb24ddb3 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: customer_contacts fk_rails_c2c8ebb3b1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_contacts
    ADD CONSTRAINT fk_rails_c2c8ebb3b1 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: service_locations fk_service_locations_customer_id_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_locations
    ADD CONSTRAINT fk_service_locations_customer_id_tenant FOREIGN KEY (organization_id, customer_id) REFERENCES public.customers(organization_id, id);


--
-- Name: audit_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;

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
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

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
-- Name: service_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_events USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- Name: catalog_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.catalog_items USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


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
-- Name: invitations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invitations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


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
-- Name: service_locations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_locations USING ((organization_id = public.servora_current_organization_id())) WITH CHECK ((organization_id = public.servora_current_organization_id()));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

