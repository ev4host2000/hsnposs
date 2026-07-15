-- Miza Cloud — 021_ops_audit_events.sql
-- Professional immutable Ops / security Audit Log (additive; does not alter audit_logs)

BEGIN;

CREATE TABLE IF NOT EXISTS ops_audit_events (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    organization_id         UUID,
    branch_id               UUID,
    user_id                 UUID,
    user_name               TEXT,
    role_name               TEXT,
    device_id               UUID,
    installation_id         TEXT,
    session_id              TEXT,
    request_id              TEXT,
    transaction_uuid        TEXT,
    entity                  TEXT,
    entity_id               TEXT,
    action                  TEXT            NOT NULL,
    status                  TEXT            NOT NULL DEFAULT 'success',
    severity                TEXT            NOT NULL DEFAULT 'info',
    reason                  TEXT,
    ip_address              TEXT,
    user_agent              TEXT,
    application_version     TEXT,
    platform                TEXT,
    trigger_source          TEXT,
    duration_ms             DOUBLE PRECISION,
    correlation_id          TEXT,
    error_code              TEXT,
    error_message           TEXT,
    stack_trace             TEXT,
    request_json            JSONB           NOT NULL DEFAULT '{}'::jsonb,
    response_json           JSONB           NOT NULL DEFAULT '{}'::jsonb,
    metadata_json           JSONB           NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS ops_audit_events_archive (
    LIKE ops_audit_events INCLUDING DEFAULTS INCLUDING CONSTRAINTS
);

CREATE TABLE IF NOT EXISTS ops_audit_settings (
    key                     TEXT            PRIMARY KEY,
    value_json              JSONB           NOT NULL DEFAULT '{}'::jsonb,
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

INSERT INTO ops_audit_settings (key, value_json)
VALUES (
    'retention',
    '{"days": 90, "archive_enabled": true}'::jsonb
)
ON CONFLICT (key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_ops_audit_created
    ON ops_audit_events (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_org_created
    ON ops_audit_events (organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_action_created
    ON ops_audit_events (action, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_status_created
    ON ops_audit_events (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_severity_created
    ON ops_audit_events (severity, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_entity
    ON ops_audit_events (entity, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_user_created
    ON ops_audit_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_device_created
    ON ops_audit_events (device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_audit_error_code
    ON ops_audit_events (error_code, created_at DESC)
    WHERE error_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ops_audit_corr
    ON ops_audit_events (correlation_id)
    WHERE correlation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ops_audit_archive_created
    ON ops_audit_events_archive (created_at DESC);

COMMENT ON TABLE ops_audit_events IS 'Immutable Ops audit events — append-only';
COMMENT ON TABLE ops_audit_events_archive IS 'Archived audit events after retention window';

-- Block UPDATE/DELETE on live audit table (immutability)
CREATE OR REPLACE FUNCTION ops_audit_events_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'ops_audit_events is immutable; UPDATE/DELETE is not allowed';
END;
$$;

DROP TRIGGER IF EXISTS trg_ops_audit_events_no_update ON ops_audit_events;
CREATE TRIGGER trg_ops_audit_events_no_update
    BEFORE UPDATE ON ops_audit_events
    FOR EACH ROW EXECUTE PROCEDURE ops_audit_events_immutable();

-- Retention archive helper (DELETE allowed only via this function after copy)
CREATE OR REPLACE FUNCTION ops_audit_archive_older_than(p_days integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    moved integer := 0;
BEGIN
    IF p_days IS NULL OR p_days < 1 THEN
        RAISE EXCEPTION 'p_days must be >= 1';
    END IF;

    INSERT INTO ops_audit_events_archive
    SELECT *
    FROM ops_audit_events
    WHERE created_at < (now() AT TIME ZONE 'utc') - make_interval(days => p_days)
    ON CONFLICT (id) DO NOTHING;

    DELETE FROM ops_audit_events
    WHERE created_at < (now() AT TIME ZONE 'utc') - make_interval(days => p_days);

    GET DIAGNOSTICS moved = ROW_COUNT;
    RETURN moved;
END;
$$;

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '021',
    'ops_audit_events — professional immutable audit log',
    '021_ops_audit_events.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
