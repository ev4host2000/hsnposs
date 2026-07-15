-- =============================================================================
-- Miza Cloud â€” install_all_flat.sql (auto-generated)
-- For phpPgAdmin / cPanel â€” do NOT use install_all.sql (\ir requires psql CLI)
-- Regenerate: .\build_install_bundle.ps1
-- =============================================================================


-- >>> BEGIN 001_initial_schema.sql

-- =============================================================================
-- Miza Cloud â€” 001_initial_schema.sql
-- PostgreSQL 15+ | Database: mizacloud
-- Tables, primary keys, column defaults â€” no foreign keys (see 003_constraints.sql)
-- =============================================================================

BEGIN;

-- Extensions ------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------------------
-- Tenancy & Settings
-- ---------------------------------------------------------------------------

CREATE TABLE companies (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT            NOT NULL,
    legal_name              TEXT,
    country_code            CHAR(2),
    timezone                TEXT            NOT NULL DEFAULT 'UTC',
    default_currency_code   TEXT            NOT NULL DEFAULT 'SAR',
    default_locale          TEXT            NOT NULL DEFAULT 'ar',
    status                  TEXT            NOT NULL DEFAULT 'active',
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE branches (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    code                    TEXT            NOT NULL,
    name                    TEXT            NOT NULL,
    address                 TEXT,
    phone                   TEXT,
    is_default              BOOLEAN         NOT NULL DEFAULT false,
    status                  TEXT            NOT NULL DEFAULT 'active',
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE organization_settings (
    company_id              UUID            PRIMARY KEY,
    settings_json           JSONB           NOT NULL DEFAULT '{}'::jsonb,
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1,
    updated_by_user_id      UUID
);

CREATE TABLE branch_settings (
    branch_id               UUID            PRIMARY KEY,
    company_id              UUID            NOT NULL,
    settings_json           JSONB           NOT NULL DEFAULT '{}'::jsonb,
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE device_settings (
    device_id               UUID            PRIMARY KEY,
    company_id              UUID            NOT NULL,
    settings_json           JSONB           NOT NULL DEFAULT '{}'::jsonb,
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

-- ---------------------------------------------------------------------------
-- Identity & Access
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    default_branch_id       UUID            NOT NULL,
    username                TEXT            NOT NULL,
    email                   CITEXT,
    full_name               TEXT            NOT NULL,
    phone                   TEXT,
    dial_code               TEXT            NOT NULL DEFAULT '+966',
    password_hash           TEXT            NOT NULL,
    role                    TEXT            NOT NULL DEFAULT 'cashier',
    account_status          TEXT            NOT NULL DEFAULT 'active',
    email_verified_at       TIMESTAMPTZ,
    last_login_at           TIMESTAMPTZ,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE user_branch_access (
    user_id                 UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    granted_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, branch_id)
);

CREATE TABLE devices (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    installation_id         TEXT            NOT NULL,
    device_fingerprint      TEXT            NOT NULL,
    platform                TEXT            NOT NULL,
    device_name             TEXT            NOT NULL,
    os_name                 TEXT            NOT NULL,
    os_user                 TEXT,
    app_version             TEXT,
    status                  TEXT            NOT NULL DEFAULT 'active',
    registered_at           TIMESTAMPTZ     NOT NULL DEFAULT now(),
    last_seen_at            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    revoked_at              TIMESTAMPTZ,
    registered_by_user_id   UUID,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE device_sessions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id               UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    user_id                 UUID,
    session_type            TEXT            NOT NULL DEFAULT 'device',
    ip_address              INET,
    user_agent              TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    last_active_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ     NOT NULL,
    revoked_at              TIMESTAMPTZ
);

CREATE TABLE api_tokens (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash              TEXT            NOT NULL,
    subject_type            TEXT            NOT NULL,
    subject_id              UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    device_session_id       UUID,
    scopes                  TEXT[]          NOT NULL DEFAULT '{}',
    issued_at               TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ     NOT NULL,
    revoked_at              TIMESTAMPTZ
);

CREATE TABLE platform_admin_tokens (
    id                      UUID            PRIMARY KEY,
    token_hash              TEXT            NOT NULL,
    scopes                  TEXT[]          NOT NULL DEFAULT '{}',
    issued_at               TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ     NOT NULL,
    revoked_at              TIMESTAMPTZ
);

CREATE TABLE refresh_tokens (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash              TEXT            NOT NULL,
    device_session_id       UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    user_id                 UUID,
    issued_at               TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ     NOT NULL,
    revoked_at              TIMESTAMPTZ,
    replaced_by_id          UUID
);

CREATE TABLE password_reset_tokens (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    token_hash              TEXT            NOT NULL,
    expires_at              TIMESTAMPTZ     NOT NULL,
    used_at                 TIMESTAMPTZ,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE email_verification_tokens (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    email                   CITEXT          NOT NULL,
    token_hash              TEXT            NOT NULL,
    expires_at              TIMESTAMPTZ     NOT NULL,
    verified_at             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Commercial / Licensing
-- ---------------------------------------------------------------------------

CREATE TABLE subscription_plans (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    code                    TEXT            NOT NULL,
    name                    TEXT            NOT NULL,
    max_devices             INTEGER         NOT NULL DEFAULT 1,
    max_branches            INTEGER,
    features_json           JSONB           NOT NULL DEFAULT '{}'::jsonb,
    is_active               BOOLEAN         NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE company_subscriptions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    plan_id                 UUID            NOT NULL,
    status                  TEXT            NOT NULL DEFAULT 'trial',
    trial_ends_at           TIMESTAMPTZ,
    current_period_start    TIMESTAMPTZ     NOT NULL DEFAULT now(),
    current_period_end      TIMESTAMPTZ     NOT NULL,
    auto_renew              BOOLEAN         NOT NULL DEFAULT true,
    external_billing_ref    TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE licenses (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    subscription_id         UUID            NOT NULL,
    license_type            TEXT            NOT NULL,
    activation_code_hash    TEXT,
    valid_from              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    valid_until             TIMESTAMPTZ,
    max_distributor_seats   INTEGER,
    features_json           JSONB           NOT NULL DEFAULT '{}'::jsonb,
    access_suspended        BOOLEAN         NOT NULL DEFAULT false,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE license_device_slots (
    license_id              UUID            NOT NULL,
    device_id               UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    bound_at                TIMESTAMPTZ     NOT NULL DEFAULT now(),
    revoked_at              TIMESTAMPTZ,
    PRIMARY KEY (license_id, device_id)
);

-- ---------------------------------------------------------------------------
-- Master Data
-- ---------------------------------------------------------------------------

CREATE TABLE product_categories (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    name                    TEXT            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE product_units (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    name                    TEXT            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE products (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    name                    TEXT            NOT NULL,
    sale_price              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    cost_price              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    stock_qty               NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    barcode                 TEXT,
    category_id             UUID,
    unit_name               TEXT,
    description             TEXT,
    image_url               TEXT,
    expiry_date             DATE,
    is_hidden               BOOLEAN         NOT NULL DEFAULT false,
    is_frozen               BOOLEAN         NOT NULL DEFAULT false,
    is_service              BOOLEAN         NOT NULL DEFAULT false,
    is_favorite             BOOLEAN         NOT NULL DEFAULT false,
    sort_order              INTEGER         NOT NULL DEFAULT 0,
    origin_device_id        UUID,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE product_sale_units (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    unit_name               TEXT            NOT NULL,
    to_base_factor          NUMERIC(18, 6)  NOT NULL DEFAULT 1,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE customers (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    customer_number         TEXT,
    name                    TEXT            NOT NULL,
    phone                   TEXT,
    address                 TEXT,
    notes                   TEXT,
    credit_limit            NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    overdue_alert_days      INTEGER,
    origin_device_id        UUID,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE suppliers (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    supplier_number         TEXT,
    name                    TEXT            NOT NULL,
    phone                   TEXT,
    address                 TEXT,
    notes                   TEXT,
    credit_limit            NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    overdue_alert_days      INTEGER,
    origin_device_id        UUID,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

-- ---------------------------------------------------------------------------
-- Transactions
-- ---------------------------------------------------------------------------

CREATE TABLE sales_invoices (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    customer_id             UUID,
    invoice_number          BIGINT,
    invoice_date            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    invoice_status          TEXT            NOT NULL DEFAULT 'draft',
    payment_type            TEXT            NOT NULL DEFAULT 'cash',
    line_subtotal           NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    tax_percent             NUMERIC(8, 4)   NOT NULL DEFAULT 0,
    total                   NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    paid_amount             NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    notes                   TEXT,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE sales_invoice_items (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id              UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    quantity                NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    unit_price              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    line_total              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE purchase_invoices (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    supplier_id             UUID,
    invoice_number          BIGINT,
    invoice_date            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    invoice_status          TEXT            NOT NULL DEFAULT 'draft',
    payment_type            TEXT            NOT NULL DEFAULT 'cash',
    line_subtotal           NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    tax_percent             NUMERIC(8, 4)   NOT NULL DEFAULT 0,
    total                   NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    paid_amount             NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    notes                   TEXT,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE purchase_invoice_items (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id              UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    quantity                NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    unit_cost               NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    line_total              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE sales_returns (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    original_invoice_id     UUID            NOT NULL,
    customer_id             UUID,
    return_number           BIGINT,
    return_date             TIMESTAMPTZ     NOT NULL DEFAULT now(),
    return_status           TEXT            NOT NULL DEFAULT 'posted',
    payment_type            TEXT            NOT NULL DEFAULT 'cash',
    line_subtotal           NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    tax_percent             NUMERIC(8, 4)   NOT NULL DEFAULT 0,
    total                   NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    paid_amount             NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    notes                   TEXT,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE sales_return_items (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    return_id               UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    original_invoice_item_id UUID,
    quantity                NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    unit_price              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    line_total              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE purchase_returns (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    original_invoice_id     UUID            NOT NULL,
    supplier_id             UUID,
    return_number           BIGINT,
    return_date             TIMESTAMPTZ     NOT NULL DEFAULT now(),
    return_status           TEXT            NOT NULL DEFAULT 'posted',
    payment_type            TEXT            NOT NULL DEFAULT 'cash',
    line_subtotal           NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    tax_percent             NUMERIC(8, 4)   NOT NULL DEFAULT 0,
    total                   NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    paid_amount             NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    notes                   TEXT,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE purchase_return_items (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    return_id               UUID            NOT NULL,
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    original_invoice_item_id UUID,
    quantity                NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    unit_cost               NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    line_total              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE invoice_payment_splits (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    invoice_kind            TEXT            NOT NULL,
    invoice_id              UUID            NOT NULL,
    payment_type            TEXT            NOT NULL,
    amount                  NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    line_order              INTEGER         NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE stock_movements (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    movement_type           TEXT            NOT NULL,
    quantity                NUMERIC(18, 4)  NOT NULL,
    reference_type          TEXT,
    reference_id            UUID,
    movement_date           TIMESTAMPTZ     NOT NULL DEFAULT now(),
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE partner_ledger (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    partner_kind            TEXT            NOT NULL,
    partner_id              UUID            NOT NULL,
    entry_type              TEXT            NOT NULL,
    reference_type          TEXT,
    reference_id            UUID,
    amount_signed           NUMERIC(18, 4)  NOT NULL,
    entry_date              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    voucher_number          TEXT,
    notes                   TEXT,
    created_by_user_id      UUID            NOT NULL,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE cash_transactions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    transaction_type        TEXT            NOT NULL,
    amount                  NUMERIC(18, 4)  NOT NULL,
    description             TEXT            NOT NULL DEFAULT '',
    reference_type          TEXT,
    reference_id            UUID,
    transaction_date        TIMESTAMPTZ     NOT NULL DEFAULT now(),
    created_by_user_id      UUID            NOT NULL,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE expenses (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    title                   TEXT            NOT NULL,
    amount                  NUMERIC(18, 4)  NOT NULL,
    expense_date            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    notes                   TEXT,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

-- ---------------------------------------------------------------------------
-- Sync & Operations
-- ---------------------------------------------------------------------------

CREATE TABLE cloud_versions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID,
    entity_scope            TEXT            NOT NULL,
    version                 BIGINT          NOT NULL DEFAULT 0,
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE sync_changelog (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID,
    sequence                BIGINT          NOT NULL,
    entity_type             TEXT            NOT NULL,
    entity_id               UUID            NOT NULL,
    operation               TEXT            NOT NULL,
    payload_json            JSONB           NOT NULL DEFAULT '{}'::jsonb,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    origin_device_id        UUID,
    origin_user_id          UUID,
    occurred_at             TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE sync_queue (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    device_id               UUID            NOT NULL,
    batch_id                UUID            NOT NULL,
    entity_type             TEXT            NOT NULL,
    entity_id               UUID            NOT NULL,
    operation               TEXT            NOT NULL,
    payload_json            JSONB           NOT NULL DEFAULT '{}'::jsonb,
    client_row_version      BIGINT,
    status                  TEXT            NOT NULL DEFAULT 'pending',
    error_code              TEXT,
    error_detail            TEXT,
    received_at             TIMESTAMPTZ     NOT NULL DEFAULT now(),
    processed_at            TIMESTAMPTZ,
    idempotency_key         TEXT            NOT NULL
);

CREATE TABLE sync_conflicts (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    device_id               UUID            NOT NULL,
    entity_type             TEXT            NOT NULL,
    entity_id               UUID            NOT NULL,
    operation               TEXT            NOT NULL,
    conflict_kind           TEXT            NOT NULL,
    status                  TEXT            NOT NULL DEFAULT 'pending',
    client_row_version      BIGINT,
    server_row_version      BIGINT,
    local_payload_json      JSONB           NOT NULL DEFAULT '{}'::jsonb,
    server_payload_json     JSONB           NOT NULL DEFAULT '{}'::jsonb,
    merged_payload_json     JSONB,
    changelog_sequence      BIGINT,
    resolution              TEXT,
    resolved_at             TIMESTAMPTZ,
    resolved_by_user_id     UUID,
    resolution_notes        TEXT,
    sync_queue_id           UUID,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Notifications & Audit
-- ---------------------------------------------------------------------------

CREATE TABLE notifications (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID,
    device_id               UUID,
    user_id                 UUID,
    kind                    TEXT            NOT NULL,
    title                   TEXT            NOT NULL,
    body                    TEXT            NOT NULL DEFAULT '',
    payload_json            JSONB,
    priority                TEXT            NOT NULL DEFAULT 'normal',
    published_at            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ
);

CREATE TABLE notification_receipts (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id         UUID            NOT NULL,
    device_id               UUID,
    user_id                 UUID,
    read_at                 TIMESTAMPTZ,
    dismissed_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID,
    actor_user_id           UUID,
    actor_device_id         UUID,
    action                  TEXT            NOT NULL,
    entity_type             TEXT,
    entity_id               UUID,
    details_json            JSONB           NOT NULL DEFAULT '{}'::jsonb,
    ip_address              INET,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMIT;


-- <<< END 001_initial_schema.sql


-- >>> BEGIN 002_indexes.sql

-- =============================================================================
-- Miza Cloud â€” 002_indexes.sql
-- Performance indexes, partial indexes, GIN â€” run after 001_initial_schema.sql
-- =============================================================================

BEGIN;

-- companies -------------------------------------------------------------------
CREATE INDEX idx_companies_status_updated
    ON companies (status, updated_at DESC);

-- branches --------------------------------------------------------------------
CREATE INDEX idx_branches_company_status
    ON branches (company_id, status);

CREATE UNIQUE INDEX uq_branches_company_code
    ON branches (company_id, code);

CREATE UNIQUE INDEX uq_branches_one_default_per_company
    ON branches (company_id)
    WHERE is_default = true;

-- organization_settings -------------------------------------------------------
CREATE INDEX idx_organization_settings_gin
    ON organization_settings USING GIN (settings_json);

-- branch_settings -------------------------------------------------------------
CREATE INDEX idx_branch_settings_company
    ON branch_settings (company_id);

CREATE INDEX idx_branch_settings_gin
    ON branch_settings USING GIN (settings_json);

-- device_settings -------------------------------------------------------------
CREATE INDEX idx_device_settings_company
    ON device_settings (company_id);

-- users -----------------------------------------------------------------------
CREATE UNIQUE INDEX uq_users_company_username
    ON users (company_id, lower(username))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_users_company_email
    ON users (company_id, lower(email::text))
    WHERE email IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_users_company_role_status
    ON users (company_id, role, account_status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_users_company_updated
    ON users (company_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- user_branch_access ----------------------------------------------------------
CREATE INDEX idx_user_branch_access_company
    ON user_branch_access (company_id);

CREATE INDEX idx_user_branch_access_branch
    ON user_branch_access (branch_id);

-- devices ---------------------------------------------------------------------
CREATE UNIQUE INDEX uq_devices_installation_id
    ON devices (installation_id);

CREATE INDEX idx_devices_company_status_last_seen
    ON devices (company_id, status, last_seen_at DESC);

-- device_sessions -------------------------------------------------------------
CREATE INDEX idx_device_sessions_device_active
    ON device_sessions (device_id, revoked_at, expires_at);

CREATE INDEX idx_device_sessions_company_last_active
    ON device_sessions (company_id, last_active_at DESC);

-- api_tokens ------------------------------------------------------------------
CREATE UNIQUE INDEX uq_api_tokens_token_hash
    ON api_tokens (token_hash);

CREATE INDEX idx_api_tokens_subject
    ON api_tokens (subject_type, subject_id, revoked_at);

CREATE INDEX idx_api_tokens_company_expires
    ON api_tokens (company_id, expires_at)
    WHERE revoked_at IS NULL;

-- platform_admin_tokens -------------------------------------------------------
CREATE UNIQUE INDEX uq_platform_admin_tokens_token_hash
    ON platform_admin_tokens (token_hash);

CREATE INDEX idx_platform_admin_tokens_active
    ON platform_admin_tokens (revoked_at, expires_at)
    WHERE revoked_at IS NULL;

-- refresh_tokens --------------------------------------------------------------
CREATE UNIQUE INDEX uq_refresh_tokens_token_hash
    ON refresh_tokens (token_hash);

CREATE INDEX idx_refresh_tokens_session
    ON refresh_tokens (device_session_id, revoked_at);

-- password_reset_tokens -------------------------------------------------------
CREATE INDEX idx_password_reset_tokens_active
    ON password_reset_tokens (user_id, expires_at)
    WHERE used_at IS NULL;

-- email_verification_tokens ---------------------------------------------------
CREATE INDEX idx_email_verification_tokens_active
    ON email_verification_tokens (user_id, expires_at)
    WHERE verified_at IS NULL;

-- subscription_plans ----------------------------------------------------------
CREATE UNIQUE INDEX uq_subscription_plans_code
    ON subscription_plans (code);

-- company_subscriptions -------------------------------------------------------
CREATE INDEX idx_company_subscriptions_company_status
    ON company_subscriptions (company_id, status);

CREATE UNIQUE INDEX uq_company_subscriptions_one_active
    ON company_subscriptions (company_id)
    WHERE status IN ('trial', 'active');

-- licenses --------------------------------------------------------------------
CREATE INDEX idx_licenses_company_type_valid
    ON licenses (company_id, license_type, valid_until);

-- license_device_slots --------------------------------------------------------
CREATE INDEX idx_license_device_slots_device
    ON license_device_slots (device_id)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_license_device_slots_company
    ON license_device_slots (company_id);

-- product_categories ----------------------------------------------------------
CREATE UNIQUE INDEX uq_product_categories_name
    ON product_categories (company_id, branch_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE INDEX idx_product_categories_branch_updated
    ON product_categories (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- product_units ---------------------------------------------------------------
CREATE UNIQUE INDEX uq_product_units_name
    ON product_units (company_id, branch_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE INDEX idx_product_units_branch_updated
    ON product_units (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- products --------------------------------------------------------------------
CREATE INDEX idx_products_barcode
    ON products (company_id, branch_id, barcode)
    WHERE barcode IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_products_branch_updated
    ON products (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_products_branch_name
    ON products (company_id, branch_id, name)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_products_category
    ON products (category_id)
    WHERE deleted_at IS NULL;

-- product_sale_units ----------------------------------------------------------
CREATE UNIQUE INDEX uq_product_sale_units_name
    ON product_sale_units (company_id, branch_id, product_id, lower(unit_name));

CREATE INDEX idx_product_sale_units_product
    ON product_sale_units (product_id);

-- customers -------------------------------------------------------------------
CREATE UNIQUE INDEX uq_customers_number
    ON customers (company_id, branch_id, customer_number)
    WHERE customer_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_customers_branch_updated
    ON customers (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_customers_branch_name
    ON customers (company_id, branch_id, name)
    WHERE deleted_at IS NULL;

-- suppliers -------------------------------------------------------------------
CREATE UNIQUE INDEX uq_suppliers_number
    ON suppliers (company_id, branch_id, supplier_number)
    WHERE supplier_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_suppliers_branch_updated
    ON suppliers (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_suppliers_branch_name
    ON suppliers (company_id, branch_id, name)
    WHERE deleted_at IS NULL;

-- sales_invoices --------------------------------------------------------------
CREATE INDEX idx_sales_invoices_branch_date
    ON sales_invoices (company_id, branch_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_sales_invoices_number
    ON sales_invoices (company_id, branch_id, invoice_number)
    WHERE invoice_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_sales_invoices_customer_date
    ON sales_invoices (customer_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_sales_invoices_branch_updated
    ON sales_invoices (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- sales_invoice_items ---------------------------------------------------------
CREATE INDEX idx_sales_invoice_items_invoice_product
    ON sales_invoice_items (invoice_id, product_id);

CREATE INDEX idx_sales_invoice_items_product
    ON sales_invoice_items (product_id);

-- purchase_invoices -----------------------------------------------------------
CREATE INDEX idx_purchase_invoices_branch_date
    ON purchase_invoices (company_id, branch_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_purchase_invoices_number
    ON purchase_invoices (company_id, branch_id, invoice_number)
    WHERE invoice_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_purchase_invoices_supplier_date
    ON purchase_invoices (supplier_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_purchase_invoices_branch_updated
    ON purchase_invoices (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- purchase_invoice_items ------------------------------------------------------
CREATE INDEX idx_purchase_invoice_items_invoice_product
    ON purchase_invoice_items (invoice_id, product_id);

-- sales_returns ---------------------------------------------------------------
CREATE INDEX idx_sales_returns_original_invoice
    ON sales_returns (original_invoice_id);

CREATE INDEX idx_sales_returns_branch_date
    ON sales_returns (company_id, branch_id, return_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_sales_returns_number
    ON sales_returns (company_id, branch_id, return_number)
    WHERE return_number IS NOT NULL AND deleted_at IS NULL;

-- sales_return_items ----------------------------------------------------------
CREATE INDEX idx_sales_return_items_return
    ON sales_return_items (return_id);

-- purchase_returns ------------------------------------------------------------
CREATE INDEX idx_purchase_returns_original_invoice
    ON purchase_returns (original_invoice_id);

CREATE INDEX idx_purchase_returns_branch_date
    ON purchase_returns (company_id, branch_id, return_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_purchase_returns_number
    ON purchase_returns (company_id, branch_id, return_number)
    WHERE return_number IS NOT NULL AND deleted_at IS NULL;

-- purchase_return_items -------------------------------------------------------
CREATE INDEX idx_purchase_return_items_return
    ON purchase_return_items (return_id);

-- invoice_payment_splits ------------------------------------------------------
CREATE INDEX idx_invoice_payment_splits_invoice
    ON invoice_payment_splits (invoice_kind, invoice_id);

CREATE INDEX idx_invoice_payment_splits_branch
    ON invoice_payment_splits (company_id, branch_id);

-- stock_movements -------------------------------------------------------------
CREATE INDEX idx_stock_movements_product_date
    ON stock_movements (company_id, branch_id, product_id, movement_date DESC);

CREATE INDEX idx_stock_movements_reference
    ON stock_movements (reference_type, reference_id);

-- partner_ledger --------------------------------------------------------------
CREATE INDEX idx_partner_ledger_partner_date
    ON partner_ledger (company_id, branch_id, partner_kind, partner_id, entry_date DESC);

CREATE INDEX idx_partner_ledger_reference
    ON partner_ledger (reference_type, reference_id);

-- cash_transactions -----------------------------------------------------------
CREATE INDEX idx_cash_transactions_branch_date
    ON cash_transactions (company_id, branch_id, transaction_date DESC);

CREATE INDEX idx_cash_transactions_reference
    ON cash_transactions (reference_type, reference_id);

-- expenses --------------------------------------------------------------------
CREATE INDEX idx_expenses_branch_date
    ON expenses (company_id, branch_id, expense_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_expenses_branch_updated
    ON expenses (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- cloud_versions --------------------------------------------------------------
CREATE UNIQUE INDEX uq_cloud_versions_scope
    ON cloud_versions (company_id, branch_id, entity_scope) NULLS NOT DISTINCT;

CREATE INDEX idx_cloud_versions_company
    ON cloud_versions (company_id, updated_at DESC);

-- sync_changelog --------------------------------------------------------------
CREATE UNIQUE INDEX uq_sync_changelog_company_sequence
    ON sync_changelog (company_id, sequence);

CREATE INDEX idx_sync_changelog_branch_occurred
    ON sync_changelog (company_id, branch_id, occurred_at DESC);

CREATE INDEX idx_sync_changelog_entity
    ON sync_changelog (company_id, entity_type, entity_id, sequence DESC);

-- sync_queue ------------------------------------------------------------------
CREATE INDEX idx_sync_queue_pending
    ON sync_queue (status, received_at)
    WHERE status = 'pending';

CREATE UNIQUE INDEX uq_sync_queue_idempotency
    ON sync_queue (device_id, idempotency_key);

CREATE INDEX idx_sync_queue_company_batch
    ON sync_queue (company_id, batch_id);

CREATE INDEX idx_sync_queue_device_status
    ON sync_queue (device_id, status, received_at DESC);

-- sync_conflicts --------------------------------------------------------------
CREATE INDEX idx_sync_conflicts_pending
    ON sync_conflicts (company_id, status, created_at DESC)
    WHERE status = 'pending';

CREATE INDEX idx_sync_conflicts_entity
    ON sync_conflicts (company_id, entity_type, entity_id);

CREATE INDEX idx_sync_conflicts_device
    ON sync_conflicts (device_id, status);

-- notifications ---------------------------------------------------------------
CREATE INDEX idx_notifications_company_published
    ON notifications (company_id, published_at DESC);

CREATE INDEX idx_notifications_branch
    ON notifications (branch_id, published_at DESC)
    WHERE branch_id IS NOT NULL;

CREATE INDEX idx_notifications_device
    ON notifications (device_id, published_at DESC)
    WHERE device_id IS NOT NULL;

-- notification_receipts -------------------------------------------------------
CREATE UNIQUE INDEX uq_notification_receipts_device
    ON notification_receipts (notification_id, device_id)
    WHERE device_id IS NOT NULL;

CREATE UNIQUE INDEX uq_notification_receipts_user
    ON notification_receipts (notification_id, user_id)
    WHERE user_id IS NOT NULL AND device_id IS NULL;

CREATE INDEX idx_notification_receipts_notification
    ON notification_receipts (notification_id);

-- audit_logs ------------------------------------------------------------------
CREATE INDEX idx_audit_logs_company_created
    ON audit_logs (company_id, created_at DESC);

CREATE INDEX idx_audit_logs_entity
    ON audit_logs (entity_type, entity_id, created_at DESC);

COMMIT;


-- <<< END 002_indexes.sql


-- >>> BEGIN 003_constraints.sql

-- =============================================================================
-- Miza Cloud â€” 003_constraints.sql
-- Foreign keys, CHECK constraints, NOT NULL business rules
-- Run after 001_initial_schema.sql and 002_indexes.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Tenancy & Settings
-- ---------------------------------------------------------------------------

ALTER TABLE branches
    ADD CONSTRAINT fk_branches_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE organization_settings
    ADD CONSTRAINT fk_organization_settings_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE branch_settings
    ADD CONSTRAINT fk_branch_settings_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE branch_settings
    ADD CONSTRAINT fk_branch_settings_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE device_settings
    ADD CONSTRAINT fk_device_settings_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE device_settings
    ADD CONSTRAINT fk_device_settings_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Identity & Access
-- ---------------------------------------------------------------------------

ALTER TABLE users
    ADD CONSTRAINT fk_users_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE users
    ADD CONSTRAINT fk_users_default_branch
        FOREIGN KEY (default_branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE organization_settings
    ADD CONSTRAINT fk_organization_settings_updated_by
        FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Identity & Access (continued)
-- ---------------------------------------------------------------------------

ALTER TABLE user_branch_access
    ADD CONSTRAINT fk_user_branch_access_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE user_branch_access
    ADD CONSTRAINT fk_user_branch_access_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE user_branch_access
    ADD CONSTRAINT fk_user_branch_access_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE devices
    ADD CONSTRAINT fk_devices_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE devices
    ADD CONSTRAINT fk_devices_registered_by
        FOREIGN KEY (registered_by_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE api_tokens
    ADD CONSTRAINT fk_api_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE api_tokens
    ADD CONSTRAINT fk_api_tokens_session
        FOREIGN KEY (device_session_id) REFERENCES device_sessions (id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_session
        FOREIGN KEY (device_session_id) REFERENCES device_sessions (id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_replaced_by
        FOREIGN KEY (replaced_by_id) REFERENCES refresh_tokens (id) ON DELETE SET NULL;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE email_verification_tokens
    ADD CONSTRAINT fk_email_verification_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE email_verification_tokens
    ADD CONSTRAINT fk_email_verification_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Commercial
-- ---------------------------------------------------------------------------

ALTER TABLE company_subscriptions
    ADD CONSTRAINT fk_company_subscriptions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE company_subscriptions
    ADD CONSTRAINT fk_company_subscriptions_plan
        FOREIGN KEY (plan_id) REFERENCES subscription_plans (id) ON DELETE RESTRICT;

ALTER TABLE licenses
    ADD CONSTRAINT fk_licenses_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE licenses
    ADD CONSTRAINT fk_licenses_subscription
        FOREIGN KEY (subscription_id) REFERENCES company_subscriptions (id) ON DELETE CASCADE;

ALTER TABLE license_device_slots
    ADD CONSTRAINT fk_license_device_slots_license
        FOREIGN KEY (license_id) REFERENCES licenses (id) ON DELETE CASCADE;

ALTER TABLE license_device_slots
    ADD CONSTRAINT fk_license_device_slots_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE license_device_slots
    ADD CONSTRAINT fk_license_device_slots_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Master Data
-- ---------------------------------------------------------------------------

ALTER TABLE product_categories
    ADD CONSTRAINT fk_product_categories_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE product_categories
    ADD CONSTRAINT fk_product_categories_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE product_units
    ADD CONSTRAINT fk_product_units_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE product_units
    ADD CONSTRAINT fk_product_units_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE products
    ADD CONSTRAINT fk_products_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE products
    ADD CONSTRAINT fk_products_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE products
    ADD CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES product_categories (id) ON DELETE SET NULL;

ALTER TABLE products
    ADD CONSTRAINT fk_products_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE product_sale_units
    ADD CONSTRAINT fk_product_sale_units_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE product_sale_units
    ADD CONSTRAINT fk_product_sale_units_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE product_sale_units
    ADD CONSTRAINT fk_product_sale_units_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE;

ALTER TABLE customers
    ADD CONSTRAINT fk_customers_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE customers
    ADD CONSTRAINT fk_customers_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE customers
    ADD CONSTRAINT fk_customers_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE suppliers
    ADD CONSTRAINT fk_suppliers_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE suppliers
    ADD CONSTRAINT fk_suppliers_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE suppliers
    ADD CONSTRAINT fk_suppliers_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Transactions
-- ---------------------------------------------------------------------------

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_invoice
        FOREIGN KEY (invoice_id) REFERENCES sales_invoices (id) ON DELETE CASCADE;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_supplier
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE SET NULL;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_invoice
        FOREIGN KEY (invoice_id) REFERENCES purchase_invoices (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_original_invoice
        FOREIGN KEY (original_invoice_id) REFERENCES sales_invoices (id) ON DELETE RESTRICT;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_return
        FOREIGN KEY (return_id) REFERENCES sales_returns (id) ON DELETE CASCADE;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_original_line
        FOREIGN KEY (original_invoice_item_id) REFERENCES sales_invoice_items (id) ON DELETE SET NULL;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_original_invoice
        FOREIGN KEY (original_invoice_id) REFERENCES purchase_invoices (id) ON DELETE RESTRICT;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_supplier
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE SET NULL;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_return
        FOREIGN KEY (return_id) REFERENCES purchase_returns (id) ON DELETE CASCADE;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_original_line
        FOREIGN KEY (original_invoice_item_id) REFERENCES purchase_invoice_items (id) ON DELETE SET NULL;

ALTER TABLE invoice_payment_splits
    ADD CONSTRAINT fk_invoice_payment_splits_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE invoice_payment_splits
    ADD CONSTRAINT fk_invoice_payment_splits_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE partner_ledger
    ADD CONSTRAINT fk_partner_ledger_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE partner_ledger
    ADD CONSTRAINT fk_partner_ledger_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE partner_ledger
    ADD CONSTRAINT fk_partner_ledger_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE cash_transactions
    ADD CONSTRAINT fk_cash_transactions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE cash_transactions
    ADD CONSTRAINT fk_cash_transactions_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE cash_transactions
    ADD CONSTRAINT fk_cash_transactions_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Sync
-- ---------------------------------------------------------------------------

ALTER TABLE cloud_versions
    ADD CONSTRAINT fk_cloud_versions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE cloud_versions
    ADD CONSTRAINT fk_cloud_versions_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_origin_user
        FOREIGN KEY (origin_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE sync_queue
    ADD CONSTRAINT fk_sync_queue_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sync_queue
    ADD CONSTRAINT fk_sync_queue_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_queue
    ADD CONSTRAINT fk_sync_queue_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_resolved_by
        FOREIGN KEY (resolved_by_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_sync_queue
        FOREIGN KEY (sync_queue_id) REFERENCES sync_queue (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys â€” Notifications & Audit
-- ---------------------------------------------------------------------------

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE notification_receipts
    ADD CONSTRAINT fk_notification_receipts_notification
        FOREIGN KEY (notification_id) REFERENCES notifications (id) ON DELETE CASCADE;

ALTER TABLE notification_receipts
    ADD CONSTRAINT fk_notification_receipts_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE notification_receipts
    ADD CONSTRAINT fk_notification_receipts_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE SET NULL;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_actor_user
        FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_actor_device
        FOREIGN KEY (actor_device_id) REFERENCES devices (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- CHECK constraints â€” enumerated values & business rules
-- ---------------------------------------------------------------------------

ALTER TABLE companies
    ADD CONSTRAINT chk_companies_status
        CHECK (status IN ('active', 'suspended', 'closed'));

ALTER TABLE branches
    ADD CONSTRAINT chk_branches_status
        CHECK (status IN ('active', 'inactive'));

ALTER TABLE users
    ADD CONSTRAINT chk_users_role
        CHECK (role IN ('owner', 'accountant', 'cashier', 'distributor', 'admin'));

ALTER TABLE users
    ADD CONSTRAINT chk_users_account_status
        CHECK (account_status IN ('active', 'disabled'));

ALTER TABLE devices
    ADD CONSTRAINT chk_devices_platform
        CHECK (platform IN ('windows', 'android', 'ios', 'web'));

ALTER TABLE devices
    ADD CONSTRAINT chk_devices_status
        CHECK (status IN ('active', 'revoked'));

ALTER TABLE device_sessions
    ADD CONSTRAINT chk_device_sessions_type
        CHECK (session_type IN ('device', 'user'));

ALTER TABLE api_tokens
    ADD CONSTRAINT chk_api_tokens_subject_type
        CHECK (subject_type IN ('user', 'device', 'service'));

ALTER TABLE company_subscriptions
    ADD CONSTRAINT chk_company_subscriptions_status
        CHECK (status IN ('trial', 'active', 'expired', 'suspended', 'cancelled'));

ALTER TABLE stock_movements
    ADD CONSTRAINT chk_stock_movements_type
        CHECK (movement_type IN ('in', 'out', 'adjust', 'transfer'));

ALTER TABLE partner_ledger
    ADD CONSTRAINT chk_partner_ledger_kind
        CHECK (partner_kind IN ('customer', 'supplier'));

ALTER TABLE cash_transactions
    ADD CONSTRAINT chk_cash_transactions_type
        CHECK (transaction_type IN ('in', 'out'));

ALTER TABLE invoice_payment_splits
    ADD CONSTRAINT chk_invoice_payment_splits_kind
        CHECK (invoice_kind IN ('sale', 'purchase', 'sales_return', 'purchase_return'));

ALTER TABLE sync_changelog
    ADD CONSTRAINT chk_sync_changelog_operation
        CHECK (operation IN ('create', 'update', 'delete', 'resolved'));

ALTER TABLE sync_queue
    ADD CONSTRAINT chk_sync_queue_status
        CHECK (status IN ('pending', 'processing', 'applied', 'rejected', 'conflict'));

ALTER TABLE sync_queue
    ADD CONSTRAINT chk_sync_queue_operation
        CHECK (operation IN ('create', 'update', 'delete'));

ALTER TABLE sync_conflicts
    ADD CONSTRAINT chk_sync_conflicts_status
        CHECK (status IN ('pending', 'resolved'));

ALTER TABLE sync_conflicts
    ADD CONSTRAINT chk_sync_conflicts_kind
        CHECK (conflict_kind IN ('row_version', 'business_rule', 'stock_negative', 'duplicate'));

ALTER TABLE sync_conflicts
    ADD CONSTRAINT chk_sync_conflicts_resolution
        CHECK (resolution IS NULL OR resolution IN ('server_wins', 'client_wins', 'merge'));

ALTER TABLE notifications
    ADD CONSTRAINT chk_notifications_priority
        CHECK (priority IN ('low', 'normal', 'high', 'urgent'));

ALTER TABLE notification_receipts
    ADD CONSTRAINT chk_notification_receipts_target
        CHECK (device_id IS NOT NULL OR user_id IS NOT NULL);

ALTER TABLE sales_invoices
    ADD CONSTRAINT chk_sales_invoices_status
        CHECK (invoice_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE purchase_invoices
    ADD CONSTRAINT chk_purchase_invoices_status
        CHECK (invoice_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE sales_returns
    ADD CONSTRAINT chk_sales_returns_status
        CHECK (return_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE purchase_returns
    ADD CONSTRAINT chk_purchase_returns_status
        CHECK (return_status IN ('draft', 'posted', 'void', 'cancelled'));

-- Non-negative amounts where applicable
ALTER TABLE products
    ADD CONSTRAINT chk_products_stock_qty_non_negative
        CHECK (stock_qty >= 0);

ALTER TABLE sales_invoices
    ADD CONSTRAINT chk_sales_invoices_totals_non_negative
        CHECK (line_subtotal >= 0 AND discount_amount >= 0 AND total >= 0 AND paid_amount >= 0);

ALTER TABLE purchase_invoices
    ADD CONSTRAINT chk_purchase_invoices_totals_non_negative
        CHECK (line_subtotal >= 0 AND discount_amount >= 0 AND total >= 0 AND paid_amount >= 0);

COMMIT;


-- <<< END 003_constraints.sql


-- >>> BEGIN 004_seed_data.sql

-- =============================================================================
-- Miza Cloud â€” 004_seed_data.sql
-- Reference / bootstrap data â€” subscription plans only (no tenant data)
-- Safe to re-run: uses ON CONFLICT DO NOTHING
-- =============================================================================

BEGIN;

INSERT INTO subscription_plans (id, code, name, max_devices, max_branches, features_json, is_active)
VALUES
    (
        'a0000001-0000-4000-8000-000000000001',
        'trial',
        'Trial â€” 14 days',
        2,
        1,
        '{"sync": true, "max_users": 3, "trial_days": 14}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000002',
        'starter',
        'Starter',
        3,
        1,
        '{"sync": true, "max_users": 5, "reports": "basic"}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000003',
        'business',
        'Business',
        10,
        5,
        '{"sync": true, "max_users": 25, "reports": "full", "multi_branch": true}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000004',
        'enterprise',
        'Enterprise',
        50,
        NULL,
        '{"sync": true, "max_users": null, "reports": "full", "multi_branch": true, "priority_support": true}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000005',
        'distributor_cloud',
        'Distributor Cloud',
        100,
        NULL,
        '{"sync": true, "distributor_mode": true, "max_distributor_seats": 50}'::jsonb,
        true
    )
ON CONFLICT (code) DO NOTHING;

COMMIT;


-- <<< END 004_seed_data.sql


-- >>> BEGIN 005_functions.sql

-- =============================================================================
-- Miza Cloud â€” 005_functions.sql
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
-- Soft delete helper â€” sets deleted_at without physical DELETE
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


-- <<< END 005_functions.sql


-- >>> BEGIN 006_triggers.sql

-- =============================================================================
-- Miza Cloud â€” 006_triggers.sql
-- updated_at / row_version triggers on syncable and audit tables
-- =============================================================================

BEGIN;

-- Tables with updated_at only (no row_version bump logic beyond touch)
CREATE TRIGGER trg_companies_touch_updated_at
    BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_branches_touch_updated_at
    BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_organization_settings_touch_updated_at
    BEFORE UPDATE ON organization_settings
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_branch_settings_touch_updated_at
    BEFORE UPDATE ON branch_settings
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_device_settings_touch_updated_at
    BEFORE UPDATE ON device_settings
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_company_subscriptions_touch_updated_at
    BEFORE UPDATE ON company_subscriptions
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_licenses_touch_updated_at
    BEFORE UPDATE ON licenses
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_sync_conflicts_touch_updated_at
    BEFORE UPDATE ON sync_conflicts
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

-- Syncable master data & transactions: bump row_version + updated_at
CREATE TRIGGER trg_users_bump_row_version
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_product_categories_bump_row_version
    BEFORE UPDATE ON product_categories
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_product_units_bump_row_version
    BEFORE UPDATE ON product_units
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_products_bump_row_version
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_product_sale_units_bump_row_version
    BEFORE UPDATE ON product_sale_units
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_customers_bump_row_version
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_suppliers_bump_row_version
    BEFORE UPDATE ON suppliers
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_invoices_bump_row_version
    BEFORE UPDATE ON sales_invoices
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_invoice_items_bump_row_version
    BEFORE UPDATE ON sales_invoice_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_invoices_bump_row_version
    BEFORE UPDATE ON purchase_invoices
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_invoice_items_bump_row_version
    BEFORE UPDATE ON purchase_invoice_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_returns_bump_row_version
    BEFORE UPDATE ON sales_returns
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_return_items_bump_row_version
    BEFORE UPDATE ON sales_return_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_returns_bump_row_version
    BEFORE UPDATE ON purchase_returns
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_return_items_bump_row_version
    BEFORE UPDATE ON purchase_return_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_invoice_payment_splits_bump_row_version
    BEFORE UPDATE ON invoice_payment_splits
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_stock_movements_bump_row_version
    BEFORE UPDATE ON stock_movements
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_partner_ledger_bump_row_version
    BEFORE UPDATE ON partner_ledger
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_cash_transactions_bump_row_version
    BEFORE UPDATE ON cash_transactions
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_expenses_bump_row_version
    BEFORE UPDATE ON expenses
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

COMMIT;


-- <<< END 006_triggers.sql


-- >>> BEGIN 007_views.sql

-- =============================================================================
-- Miza Cloud â€” 007_views.sql
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


-- <<< END 007_views.sql


-- >>> BEGIN 008_permissions.sql

-- =============================================================================
-- Miza Cloud â€” 008_permissions.sql
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

COMMENT ON ROLE mizacloud IS 'Miza Cloud API runtime â€” DML only';
COMMENT ON ROLE mizacloud_migrate IS 'Miza Cloud migrations â€” DDL + DML';

COMMIT;


-- <<< END 008_permissions.sql


-- >>> BEGIN 009_migrations.sql

-- =============================================================================
-- Miza Cloud â€” 009_migrations.sql
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
    ('001', 'initial_schema â€” 43 tables, UUID PKs, extensions', '001_initial_schema.sql'),
    ('002', 'indexes â€” performance, partial unique, GIN', '002_indexes.sql'),
    ('003', 'constraints â€” foreign keys, CHECK enums', '003_constraints.sql'),
    ('004', 'seed_data â€” subscription_plans reference rows', '004_seed_data.sql'),
    ('005', 'functions â€” updated_at, row_version, sync sequence', '005_functions.sql'),
    ('006', 'triggers â€” auto bump row_version on syncable tables', '006_triggers.sql'),
    ('007', 'views â€” active rows, sync queue, conflicts', '007_views.sql'),
    ('008', 'permissions â€” mizacloud / mizacloud_migrate roles', '008_permissions.sql')
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 009_migrations.sql


-- >>> BEGIN 010_catalog_taxes_price_lists.sql

-- =============================================================================
-- Miza Cloud â€” 010_catalog_taxes_price_lists.sql
-- Taxes, price lists, optional sort_order on product_categories
-- =============================================================================

BEGIN;

ALTER TABLE product_categories
    ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS taxes (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    name                    TEXT            NOT NULL,
    percent                 NUMERIC(8, 4)   NOT NULL DEFAULT 0,
    is_default              BOOLEAN         NOT NULL DEFAULT false,
    sort_order              INTEGER         NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS price_lists (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    name                    TEXT            NOT NULL,
    is_default              BOOLEAN         NOT NULL DEFAULT false,
    sort_order              INTEGER         NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS price_list_items (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    price_list_id           UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    sale_price              NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    row_version             BIGINT          NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_taxes_company_branch
    ON taxes (company_id, branch_id)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_taxes_company_branch_name
    ON taxes (company_id, branch_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_price_lists_company_branch
    ON price_lists (company_id, branch_id)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_price_lists_company_branch_name
    ON price_lists (company_id, branch_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_price_list_items_list
    ON price_list_items (price_list_id)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_price_list_items_list_product
    ON price_list_items (price_list_id, product_id)
    WHERE deleted_at IS NULL;

ALTER TABLE taxes
    ADD CONSTRAINT fk_taxes_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE taxes
    ADD CONSTRAINT fk_taxes_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE price_lists
    ADD CONSTRAINT fk_price_lists_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE price_lists
    ADD CONSTRAINT fk_price_lists_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE price_list_items
    ADD CONSTRAINT fk_price_list_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE price_list_items
    ADD CONSTRAINT fk_price_list_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE price_list_items
    ADD CONSTRAINT fk_price_list_items_list
        FOREIGN KEY (price_list_id) REFERENCES price_lists (id) ON DELETE CASCADE;

ALTER TABLE price_list_items
    ADD CONSTRAINT fk_price_list_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE;

CREATE TRIGGER trg_taxes_bump_row_version
    BEFORE UPDATE ON taxes
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_price_lists_bump_row_version
    BEFORE UPDATE ON price_lists
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_price_list_items_bump_row_version
    BEFORE UPDATE ON price_list_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

INSERT INTO schema_migrations (version, description, checksum)
VALUES ('010', 'catalog_taxes_price_lists â€” taxes, price_lists, sort_order', '010_catalog_taxes_price_lists.sql')
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 010_catalog_taxes_price_lists.sql


-- >>> BEGIN 011_sales_invoice_transaction_version.sql

-- =============================================================================
-- Miza Cloud â€” 011_sales_invoice_transaction_version.sql
-- Adds transaction_version for ADR-TX draft lifecycle on sales_invoices
-- =============================================================================

BEGIN;

ALTER TABLE sales_invoices
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

COMMENT ON COLUMN sales_invoices.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

ALTER TABLE sync_changelog
    DROP CONSTRAINT IF EXISTS chk_sync_changelog_operation;

ALTER TABLE sync_changelog
    ADD CONSTRAINT chk_sync_changelog_operation
        CHECK (operation IN ('create', 'update', 'delete', 'cancel', 'post', 'resolved'));

ALTER TABLE sync_queue
    DROP CONSTRAINT IF EXISTS chk_sync_queue_operation;

ALTER TABLE sync_queue
    ADD CONSTRAINT chk_sync_queue_operation
        CHECK (operation IN ('create', 'update', 'delete', 'cancel', 'post'));

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '011',
    'sales_invoice transaction_version column',
    '011_sales_invoice_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 011_sales_invoice_transaction_version.sql


-- >>> BEGIN 012_sales_invoice_posted_at.sql

-- =============================================================================
-- Miza Cloud â€” 012_sales_invoice_posted_at.sql
-- Adds posted_at for sales invoice post lifecycle
-- =============================================================================

BEGIN;

ALTER TABLE sales_invoices
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN sales_invoices.posted_at IS
    'Timestamp when invoice was posted (inventory + accounting applied)';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '012',
    'sales_invoice posted_at column',
    '012_sales_invoice_posted_at.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 012_sales_invoice_posted_at.sql


-- >>> BEGIN 013_purchase_invoice_transaction_version.sql

-- =============================================================================
-- Miza Cloud â€” 013_purchase_invoice_transaction_version.sql
-- Adds transaction_version + posted_at for ADR-TX draft lifecycle on purchase_invoices
-- =============================================================================

BEGIN;

ALTER TABLE purchase_invoices
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE purchase_invoices
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN purchase_invoices.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '013',
    'purchase_invoice transaction_version column',
    '013_purchase_invoice_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 013_purchase_invoice_transaction_version.sql


-- >>> BEGIN 014_return_transaction_version.sql

-- =============================================================================
-- Miza Cloud â€” 014_return_transaction_version.sql
-- Adds transaction_version + posted_at for ADR-TX draft lifecycle on returns
-- =============================================================================

BEGIN;

ALTER TABLE sales_returns
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE sales_returns
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN sales_returns.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

ALTER TABLE purchase_returns
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE purchase_returns
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN purchase_returns.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '014',
    'sales_return and purchase_return transaction_version columns',
    '014_return_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 014_return_transaction_version.sql


-- >>> BEGIN 015_payment_transaction_version.sql

-- =============================================================================
-- Miza Cloud â€” 015_payment_transaction_version.sql
-- Customer/supplier payment tables for ADR-TX draft lifecycle (Feature Pack 2)
-- =============================================================================

BEGIN;

CREATE TABLE customer_payments (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    customer_id             UUID,
    amount                  NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    payment_date            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    payment_method          TEXT            NOT NULL DEFAULT 'cash',
    voucher_number          TEXT,
    notes                   TEXT,
    payment_status          TEXT            NOT NULL DEFAULT 'draft',
    transaction_version     BIGINT          NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    posted_at               TIMESTAMPTZ,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ
);

CREATE TABLE supplier_payments (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    supplier_id             UUID,
    amount                  NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    payment_date            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    payment_method          TEXT            NOT NULL DEFAULT 'cash',
    voucher_number          TEXT,
    notes                   TEXT,
    payment_status          TEXT            NOT NULL DEFAULT 'draft',
    transaction_version     BIGINT          NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    posted_at               TIMESTAMPTZ,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ
);

COMMENT ON COLUMN customer_payments.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

COMMENT ON COLUMN supplier_payments.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

-- Indexes -------------------------------------------------------------------
CREATE INDEX idx_customer_payments_branch_date
    ON customer_payments (company_id, branch_id, payment_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_customer_payments_customer
    ON customer_payments (customer_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_supplier_payments_branch_date
    ON supplier_payments (company_id, branch_id, payment_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_supplier_payments_supplier
    ON supplier_payments (supplier_id)
    WHERE deleted_at IS NULL;

-- Foreign keys --------------------------------------------------------------
ALTER TABLE customer_payments
    ADD CONSTRAINT fk_customer_payments_company
        FOREIGN KEY (company_id) REFERENCES companies (id);

ALTER TABLE customer_payments
    ADD CONSTRAINT fk_customer_payments_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id);

ALTER TABLE customer_payments
    ADD CONSTRAINT fk_customer_payments_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id);

ALTER TABLE customer_payments
    ADD CONSTRAINT fk_customer_payments_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE customer_payments
    ADD CONSTRAINT fk_customer_payments_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id);

ALTER TABLE supplier_payments
    ADD CONSTRAINT fk_supplier_payments_company
        FOREIGN KEY (company_id) REFERENCES companies (id);

ALTER TABLE supplier_payments
    ADD CONSTRAINT fk_supplier_payments_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id);

ALTER TABLE supplier_payments
    ADD CONSTRAINT fk_supplier_payments_supplier
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id);

ALTER TABLE supplier_payments
    ADD CONSTRAINT fk_supplier_payments_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE supplier_payments
    ADD CONSTRAINT fk_supplier_payments_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id);

-- Check constraints ---------------------------------------------------------
ALTER TABLE customer_payments
    ADD CONSTRAINT chk_customer_payments_status
        CHECK (payment_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE customer_payments
    ADD CONSTRAINT chk_customer_payments_amount_non_negative
        CHECK (amount >= 0);

ALTER TABLE supplier_payments
    ADD CONSTRAINT chk_supplier_payments_status
        CHECK (payment_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE supplier_payments
    ADD CONSTRAINT chk_supplier_payments_amount_non_negative
        CHECK (amount >= 0);

-- Row-version triggers ------------------------------------------------------
CREATE TRIGGER trg_customer_payments_bump_row_version
    BEFORE UPDATE ON customer_payments
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_supplier_payments_bump_row_version
    BEFORE UPDATE ON supplier_payments
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '015',
    'customer_payments and supplier_payments tables',
    '015_payment_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 015_payment_transaction_version.sql


-- >>> BEGIN 016_inventory_adjustment_transaction_version.sql

-- =============================================================================
-- Miza Cloud â€” 016_inventory_adjustment_transaction_version.sql
-- Inventory adjustment table for ADR-TX draft lifecycle (Feature Pack 3A)
-- =============================================================================

BEGIN;

CREATE TABLE inventory_adjustments (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    quantity_delta          NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    adjustment_date         TIMESTAMPTZ     NOT NULL DEFAULT now(),
    adjustment_status       TEXT            NOT NULL DEFAULT 'draft',
    notes                   TEXT,
    reason                  TEXT,
    transaction_version     BIGINT          NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    posted_at               TIMESTAMPTZ,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ
);

COMMENT ON COLUMN inventory_adjustments.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

COMMENT ON COLUMN inventory_adjustments.quantity_delta IS
    'Signed stock change applied on post (positive = increase, negative = decrease)';

-- Indexes -------------------------------------------------------------------
CREATE INDEX idx_inventory_adjustments_branch_date
    ON inventory_adjustments (company_id, branch_id, adjustment_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_inventory_adjustments_product
    ON inventory_adjustments (product_id)
    WHERE deleted_at IS NULL;

-- Foreign keys --------------------------------------------------------------
ALTER TABLE inventory_adjustments
    ADD CONSTRAINT fk_inventory_adjustments_company
        FOREIGN KEY (company_id) REFERENCES companies (id);

ALTER TABLE inventory_adjustments
    ADD CONSTRAINT fk_inventory_adjustments_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id);

ALTER TABLE inventory_adjustments
    ADD CONSTRAINT fk_inventory_adjustments_product
        FOREIGN KEY (product_id) REFERENCES products (id);

ALTER TABLE inventory_adjustments
    ADD CONSTRAINT fk_inventory_adjustments_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE inventory_adjustments
    ADD CONSTRAINT fk_inventory_adjustments_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id);

-- Check constraints ---------------------------------------------------------
ALTER TABLE inventory_adjustments
    ADD CONSTRAINT chk_inventory_adjustments_status
        CHECK (adjustment_status IN ('draft', 'posted', 'void', 'cancelled'));

-- Row-version triggers ------------------------------------------------------
CREATE TRIGGER trg_inventory_adjustments_bump_row_version
    BEFORE UPDATE ON inventory_adjustments
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '016',
    'inventory_adjustments table with transaction_version',
    '016_inventory_adjustment_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 016_inventory_adjustment_transaction_version.sql


-- >>> BEGIN 017_opening_stock_transaction_version.sql

-- =============================================================================
-- Miza Cloud â€” 017_opening_stock_transaction_version.sql
-- Opening stock table for ADR-TX draft lifecycle (Feature Pack 3B)
-- =============================================================================

BEGIN;

CREATE TABLE opening_stocks (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id              UUID            NOT NULL,
    branch_id               UUID            NOT NULL,
    product_id              UUID            NOT NULL,
    opening_quantity        NUMERIC(18, 4)  NOT NULL DEFAULT 0,
    opening_date            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    opening_status          TEXT            NOT NULL DEFAULT 'draft',
    notes                   TEXT,
    transaction_version     BIGINT          NOT NULL DEFAULT 0,
    row_version             BIGINT          NOT NULL DEFAULT 1,
    posted_at               TIMESTAMPTZ,
    created_by_user_id      UUID            NOT NULL,
    origin_device_id        UUID            NOT NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ
);

COMMENT ON COLUMN opening_stocks.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) â€” separate from row_version';

COMMENT ON COLUMN opening_stocks.opening_quantity IS
    'Positive stock quantity applied on post (opening balance increase)';

-- Indexes -------------------------------------------------------------------
CREATE INDEX idx_opening_stocks_branch_date
    ON opening_stocks (company_id, branch_id, opening_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_opening_stocks_product
    ON opening_stocks (product_id)
    WHERE deleted_at IS NULL;

-- Foreign keys --------------------------------------------------------------
ALTER TABLE opening_stocks
    ADD CONSTRAINT fk_opening_stocks_company
        FOREIGN KEY (company_id) REFERENCES companies (id);

ALTER TABLE opening_stocks
    ADD CONSTRAINT fk_opening_stocks_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id);

ALTER TABLE opening_stocks
    ADD CONSTRAINT fk_opening_stocks_product
        FOREIGN KEY (product_id) REFERENCES products (id);

ALTER TABLE opening_stocks
    ADD CONSTRAINT fk_opening_stocks_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE opening_stocks
    ADD CONSTRAINT fk_opening_stocks_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id);

-- Check constraints ---------------------------------------------------------
ALTER TABLE opening_stocks
    ADD CONSTRAINT chk_opening_stocks_status
        CHECK (opening_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE opening_stocks
    ADD CONSTRAINT chk_opening_stocks_quantity_positive
        CHECK (opening_quantity >= 0);

-- Row-version triggers ------------------------------------------------------
CREATE TRIGGER trg_opening_stocks_bump_row_version
    BEFORE UPDATE ON opening_stocks
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '017',
    'opening_stocks table with transaction_version',
    '017_opening_stock_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;


-- <<< END 017_opening_stock_transaction_version.sql

