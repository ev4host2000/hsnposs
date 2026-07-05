-- =============================================================================
-- Miza Cloud — 010_catalog_taxes_price_lists.sql
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
VALUES ('010', 'catalog_taxes_price_lists — taxes, price_lists, sort_order', '010_catalog_taxes_price_lists.sql')
ON CONFLICT (version) DO NOTHING;

COMMIT;
