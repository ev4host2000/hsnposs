-- =============================================================================
-- Miza Cloud — 017_opening_stock_transaction_version.sql
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
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

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
