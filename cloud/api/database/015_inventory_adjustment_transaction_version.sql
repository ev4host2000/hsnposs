-- =============================================================================
-- Miza Cloud — 015_inventory_adjustment_transaction_version.sql
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
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

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
    '015',
    'inventory_adjustments table with transaction_version',
    '015_inventory_adjustment_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
