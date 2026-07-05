-- =============================================================================
-- Miza Cloud — 007_views.sql
-- Read-only views for API queries, sync pull helpers, active-row filtering
-- =============================================================================

BEGIN;

-- Active tenants ----------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_companies AS
SELECT *
FROM companies
WHERE status = 'active';

CREATE OR REPLACE VIEW v_active_branches AS
SELECT b.*
FROM branches b
INNER JOIN companies c ON c.id = b.company_id
WHERE b.status = 'active'
  AND c.status = 'active';

-- Active master data (soft-delete aware) ----------------------------------------
CREATE OR REPLACE VIEW v_active_products AS
SELECT p.*
FROM products p
INNER JOIN branches b ON b.id = p.branch_id
WHERE p.deleted_at IS NULL
  AND b.status = 'active';

CREATE OR REPLACE VIEW v_active_customers AS
SELECT c.*
FROM customers c
WHERE c.deleted_at IS NULL;

CREATE OR REPLACE VIEW v_active_suppliers AS
SELECT s.*
FROM suppliers s
WHERE s.deleted_at IS NULL;

CREATE OR REPLACE VIEW v_active_users AS
SELECT u.*
FROM users u
WHERE u.deleted_at IS NULL
  AND u.account_status = 'active';

-- Sync operations ---------------------------------------------------------------
CREATE OR REPLACE VIEW v_pending_sync_queue AS
SELECT sq.*
FROM sync_queue sq
WHERE sq.status = 'pending'
ORDER BY sq.received_at ASC;

CREATE OR REPLACE VIEW v_pending_sync_conflicts AS
SELECT sc.*
FROM sync_conflicts sc
WHERE sc.status = 'pending'
ORDER BY sc.created_at ASC;

CREATE OR REPLACE VIEW v_sync_changelog_recent AS
SELECT
    cl.id,
    cl.company_id,
    cl.branch_id,
    cl.sequence,
    cl.entity_type,
    cl.entity_id,
    cl.operation,
    cl.row_version,
    cl.origin_device_id,
    cl.origin_user_id,
    cl.occurred_at
FROM sync_changelog cl
ORDER BY cl.company_id, cl.sequence DESC;

-- Device health -----------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_devices AS
SELECT d.*
FROM devices d
WHERE d.status = 'active'
  AND d.revoked_at IS NULL;

CREATE OR REPLACE VIEW v_device_sessions_active AS
SELECT ds.*
FROM device_sessions ds
INNER JOIN devices d ON d.id = ds.device_id
WHERE ds.revoked_at IS NULL
  AND ds.expires_at > now()
  AND d.status = 'active';

-- Notifications -----------------------------------------------------------------
CREATE OR REPLACE VIEW v_notifications_active AS
SELECT n.*
FROM notifications n
WHERE n.expires_at IS NULL OR n.expires_at > now()
ORDER BY n.published_at DESC;

-- Licensing ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_company_subscription_current AS
SELECT DISTINCT ON (cs.company_id)
    cs.*
FROM company_subscriptions cs
WHERE cs.status IN ('trial', 'active')
ORDER BY cs.company_id, cs.current_period_end DESC;

COMMENT ON VIEW v_active_products IS 'Products visible to catalog:read (non-deleted)';
COMMENT ON VIEW v_pending_sync_queue IS 'Ingest queue awaiting worker processing';
COMMENT ON VIEW v_pending_sync_conflicts IS 'Conflicts requiring manual or policy resolution';

COMMIT;
