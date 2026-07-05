-- =============================================================================
-- Miza Cloud — 008_permissions.sql
-- Database roles and grants for API runtime vs migration tooling
--
-- Usage (as superuser):
--   psql -U postgres -d mizacloud -f 008_permissions.sql
--   psql -U postgres -d mizacloud -c "ALTER ROLE mizacloud LOGIN PASSWORD '...';"
-- =============================================================================

BEGIN;

-- Roles -----------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mizacloud_migrate') THEN
        CREATE ROLE mizacloud_migrate;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mizacloud') THEN
        CREATE ROLE mizacloud;
    END IF;
END
$$;

-- Migration role: DDL + DML (CI / DBA only)
GRANT CONNECT ON DATABASE mizacloud TO mizacloud_migrate;
GRANT USAGE, CREATE ON SCHEMA public TO mizacloud_migrate;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mizacloud_migrate;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mizacloud_migrate;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO mizacloud_migrate;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO mizacloud_migrate;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO mizacloud_migrate;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO mizacloud_migrate;

-- Application role: DML only (PHP API runtime)
GRANT CONNECT ON DATABASE mizacloud TO mizacloud;
GRANT USAGE ON SCHEMA public TO mizacloud;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mizacloud;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mizacloud;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO mizacloud;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mizacloud;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO mizacloud;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO mizacloud;

-- Views (read paths)
GRANT SELECT ON
    v_active_companies,
    v_active_branches,
    v_active_products,
    v_active_customers,
    v_active_suppliers,
    v_active_users,
    v_pending_sync_queue,
    v_pending_sync_conflicts,
    v_sync_changelog_recent,
    v_active_devices,
    v_device_sessions_active,
    v_notifications_active,
    v_company_subscription_current
TO mizacloud;

-- Revoke dangerous operations from app role
REVOKE CREATE ON SCHEMA public FROM mizacloud;
REVOKE TRUNCATE ON ALL TABLES IN SCHEMA public FROM mizacloud;

COMMENT ON ROLE mizacloud IS 'Miza Cloud API runtime — DML only';
COMMENT ON ROLE mizacloud_migrate IS 'Miza Cloud migrations — DDL + DML';

COMMIT;
