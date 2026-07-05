-- =============================================================================
-- Miza Cloud — 009_migrations.sql
-- Schema migration tracking table + baseline version records
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
    id              SERIAL          PRIMARY KEY,
    version         TEXT            NOT NULL,
    description     TEXT            NOT NULL DEFAULT '',
    checksum        TEXT,
    applied_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    applied_by      TEXT            NOT NULL DEFAULT current_user,
    execution_ms    INTEGER,
    CONSTRAINT uq_schema_migrations_version UNIQUE (version)
);

CREATE INDEX IF NOT EXISTS idx_schema_migrations_applied_at
    ON schema_migrations (applied_at DESC);

COMMENT ON TABLE schema_migrations IS 'Tracks applied SQL migration files for mizacloud database';

-- Baseline: idempotent insert of bundled migration set
INSERT INTO schema_migrations (version, description, checksum)
VALUES
    ('001', 'initial_schema — 43 tables, UUID PKs, extensions', '001_initial_schema.sql'),
    ('002', 'indexes — performance, partial unique, GIN', '002_indexes.sql'),
    ('003', 'constraints — foreign keys, CHECK enums', '003_constraints.sql'),
    ('004', 'seed_data — subscription_plans reference rows', '004_seed_data.sql'),
    ('005', 'functions — updated_at, row_version, sync sequence', '005_functions.sql'),
    ('006', 'triggers — auto bump row_version on syncable tables', '006_triggers.sql'),
    ('007', 'views — active rows, sync queue, conflicts', '007_views.sql'),
    ('008', 'permissions — mizacloud / mizacloud_migrate roles', '008_permissions.sql')
ON CONFLICT (version) DO NOTHING;

COMMIT;
