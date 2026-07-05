-- =============================================================================
-- Miza Cloud — 001_initial_schema.sql
-- PostgreSQL 15+ | Database: mizacloud
-- Tables, primary keys, column defaults — no foreign keys (see 003_constraints.sql)
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
