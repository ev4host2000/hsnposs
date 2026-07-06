-- =============================================================================
-- Miza Cloud — 014_payment_transaction_version.sql
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
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

COMMENT ON COLUMN supplier_payments.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

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
    '014',
    'customer_payments and supplier_payments tables',
    '014_payment_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
