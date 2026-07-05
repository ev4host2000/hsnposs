-- =============================================================================
-- Miza Cloud — 005_functions.sql
-- Shared PostgreSQL functions for timestamps, row_version, sync sequencing
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Auto-touch updated_at on UPDATE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION miza_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Bump row_version on UPDATE (syncable entities)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION miza_bump_row_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.row_version := COALESCE(OLD.row_version, 0) + 1;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Soft delete helper — sets deleted_at without physical DELETE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION miza_soft_delete(
    p_table regclass,
    p_id UUID,
    p_company_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
    v_rows INTEGER;
BEGIN
    v_sql := format(
        'UPDATE %s SET deleted_at = now(), updated_at = now(), row_version = row_version + 1
         WHERE id = $1 AND deleted_at IS NULL',
        p_table
    );

    IF p_company_id IS NOT NULL THEN
        v_sql := v_sql || ' AND company_id = $2';
        EXECUTE v_sql USING p_id, p_company_id;
    ELSE
        EXECUTE v_sql USING p_id;
    END IF;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

-- ---------------------------------------------------------------------------
-- Per-company monotonic sync sequence (for sync_changelog.sequence)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_sequence_counters (
    company_id      UUID        PRIMARY KEY,
    last_sequence   BIGINT      NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_sync_sequence_counters_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION miza_next_sync_sequence(p_company_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_sequence BIGINT;
BEGIN
    INSERT INTO sync_sequence_counters (company_id, last_sequence)
    VALUES (p_company_id, 1)
    ON CONFLICT (company_id) DO UPDATE
        SET last_sequence = sync_sequence_counters.last_sequence + 1,
            updated_at = now()
    RETURNING last_sequence INTO v_sequence;

    RETURN v_sequence;
END;
$$;

-- Reserve a block of sequences (batch ingest)
CREATE OR REPLACE FUNCTION miza_reserve_sync_sequences(
    p_company_id UUID,
    p_count INTEGER
)
RETURNS TABLE (start_sequence BIGINT, end_sequence BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start BIGINT;
    v_end BIGINT;
BEGIN
    IF p_count < 1 THEN
        RAISE EXCEPTION 'p_count must be >= 1';
    END IF;

    INSERT INTO sync_sequence_counters (company_id, last_sequence)
    VALUES (p_company_id, p_count)
    ON CONFLICT (company_id) DO UPDATE
        SET last_sequence = sync_sequence_counters.last_sequence + p_count,
            updated_at = now()
    RETURNING last_sequence INTO v_end;

    v_start := v_end - p_count + 1;
    start_sequence := v_start;
    end_sequence := v_end;
    RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- Bump cloud_versions after changelog write
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION miza_bump_cloud_version(
    p_company_id UUID,
    p_branch_id UUID,
    p_entity_scope TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_version BIGINT;
BEGIN
    INSERT INTO cloud_versions (company_id, branch_id, entity_scope, version, updated_at)
    VALUES (p_company_id, p_branch_id, p_entity_scope, 1, now())
    ON CONFLICT (company_id, branch_id, entity_scope)
    DO UPDATE SET
        version = cloud_versions.version + 1,
        updated_at = now()
    RETURNING version INTO v_version;

    RETURN v_version;
END;
$$;

COMMENT ON FUNCTION miza_touch_updated_at() IS 'Trigger helper: set updated_at = now()';
COMMENT ON FUNCTION miza_bump_row_version() IS 'Trigger helper: increment row_version and touch updated_at';
COMMENT ON FUNCTION miza_next_sync_sequence(UUID) IS 'Atomic per-company sequence for sync_changelog';
COMMENT ON FUNCTION miza_bump_cloud_version(UUID, UUID, TEXT) IS 'Increment cloud_versions counter for pull cursor';

COMMIT;
