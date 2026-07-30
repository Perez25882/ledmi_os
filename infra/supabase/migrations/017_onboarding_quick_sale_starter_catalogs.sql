-- 017_onboarding_quick_sale_starter_catalogs.sql
-- LedgerMind OS MVP — Onboarding, quick-sale, and starter catalog support.
--
-- Adds:
--   * business_types            — reference data for onboarding business-type picker
--   * starter_catalog_templates — pre-built product templates per business type
--   * barcode_cache             — cached results from barcode lookup services
--   * sale_items.is_quick_sale / quick_sale_name — ad-hoc quick-sale line items
--   * businesses.business_type / onboarding_completed — onboarding state
--   * process_stock_in() RPC    — idempotent inventory delivery recording
--
-- Notes:
--   * Idempotent throughout (CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
--     CREATE OR REPLACE FUNCTION, CREATE INDEX IF NOT EXISTS).
--   * inventory is keyed per (product_id, branch_id) with a reorder_level column
--     (see 002_branch_model.sql and 010_inventory_reorder_level.sql).
--   * inventory_logs columns: id, business_id, branch_id, product_id,
--     old_quantity, new_quantity, change_amount, reason, actor_id, created_at.
--     An idempotency_key column is added here to support safe retry of stock-in.


-- ============================================================
-- 1. business_types (reference data)
-- ============================================================

CREATE TABLE IF NOT EXISTS business_types (
    id   TEXT PRIMARY KEY,  -- 'supermarket', 'pharmacy', 'electronics', 'fashion', 'hardware', 'other'
    name TEXT NOT NULL,
    icon TEXT               -- material icon name for Flutter
);


-- ============================================================
-- 2. starter_catalog_templates (pre-built product templates)
-- ============================================================

CREATE TABLE IF NOT EXISTS starter_catalog_templates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_type   TEXT NOT NULL REFERENCES business_types(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    barcode         TEXT,
    category        TEXT NOT NULL,
    suggested_price NUMERIC(10,2) NOT NULL,
    suggested_cost  NUMERIC(10,2),
    unit            TEXT NOT NULL DEFAULT 'piece',
    image_url       TEXT,
    sort_order      INT  NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_starter_catalog_type ON starter_catalog_templates(business_type);


-- ============================================================
-- 3. barcode_cache (cached barcode lookup results)
-- ============================================================

CREATE TABLE IF NOT EXISTS barcode_cache (
    barcode          TEXT PRIMARY KEY,
    name             TEXT NOT NULL,
    category         TEXT,
    brand            TEXT,
    image_url        TEXT,
    suggested_price  NUMERIC(10,2),
    source           TEXT NOT NULL DEFAULT 'open_food_facts',
    cached_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 4. sale_items: quick-sale support
-- ============================================================

ALTER TABLE sale_items
    ADD COLUMN IF NOT EXISTS is_quick_sale    BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS quick_sale_name  TEXT;


-- ============================================================
-- 5. businesses: onboarding state
-- ============================================================

ALTER TABLE businesses
    ADD COLUMN IF NOT EXISTS business_type        TEXT REFERENCES business_types(id);

ALTER TABLE businesses
    ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN NOT NULL DEFAULT false;


-- ============================================================
-- 6. inventory_logs: idempotency key for stock-in retries
-- ============================================================

ALTER TABLE inventory_logs
    ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE INDEX IF NOT EXISTS idx_inventory_logs_idempotency
    ON inventory_logs(idempotency_key) WHERE idempotency_key IS NOT NULL;


-- ============================================================
-- 7. Row Level Security
-- ============================================================

ALTER TABLE business_types            ENABLE ROW LEVEL SECURITY;
ALTER TABLE starter_catalog_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE barcode_cache             ENABLE ROW LEVEL SECURITY;

-- business_types: public read (reference data)
DROP POLICY IF EXISTS business_types_public_read ON business_types;
CREATE POLICY business_types_public_read
    ON business_types FOR SELECT
    TO anon, authenticated
    USING (true);

-- starter_catalog_templates: public read (reference data)
DROP POLICY IF EXISTS starter_catalog_templates_public_read ON starter_catalog_templates;
CREATE POLICY starter_catalog_templates_public_read
    ON starter_catalog_templates FOR SELECT
    TO anon, authenticated
    USING (true);

-- barcode_cache: authenticated read + write (any logged-in user can read and contribute)
DROP POLICY IF EXISTS barcode_cache_auth_read ON barcode_cache;
CREATE POLICY barcode_cache_auth_read
    ON barcode_cache FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS barcode_cache_auth_write ON barcode_cache;
CREATE POLICY barcode_cache_auth_write
    ON barcode_cache FOR INSERT
    TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS barcode_cache_auth_update ON barcode_cache;
CREATE POLICY barcode_cache_auth_update
    ON barcode_cache FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);


-- ============================================================
-- 8. process_stock_in() — idempotent inventory delivery RPC
-- ============================================================
-- Records an inventory delivery (stock-in) for a branch/product pair.
-- Idempotent: repeated calls with the same idempotency_key are no-ops.
-- Adjusted to the real inventory / inventory_logs schema:
--   * inventory PK is (product_id, branch_id); has reorder_level, no `id`.
--   * inventory_logs records old_quantity, new_quantity, change_amount,
--     reason, actor_id (auth.uid()).

CREATE OR REPLACE FUNCTION process_stock_in(
    p_branch_id       UUID,
    p_product_id      UUID,
    p_quantity        INT,
    p_reason          TEXT DEFAULT 'delivery',
    p_idempotency_key TEXT DEFAULT gen_random_uuid()::text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_business_id  UUID;
    v_current_qty  INT;
BEGIN
    SELECT business_id INTO v_business_id FROM branches WHERE id = p_branch_id;
    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Branch not found';
    END IF;

    -- Idempotency check: skip if this key was already processed
    IF EXISTS (
        SELECT 1 FROM inventory_logs
        WHERE idempotency_key = p_idempotency_key
    ) THEN
        RETURN;
    END IF;

    -- Get current quantity (inventory keyed by product_id + branch_id)
    SELECT quantity INTO v_current_qty
    FROM inventory
    WHERE product_id = p_product_id AND branch_id = p_branch_id;

    -- Update or insert inventory
    IF v_current_qty IS NULL THEN
        INSERT INTO inventory (product_id, branch_id, business_id, quantity, reorder_level)
        VALUES (p_product_id, p_branch_id, v_business_id, p_quantity, 5);
        v_current_qty := 0;
    ELSE
        UPDATE inventory
        SET quantity = v_current_qty + p_quantity,
            updated_at = now()
        WHERE product_id = p_product_id AND branch_id = p_branch_id;
    END IF;

    -- Log the stock change (immutable audit trail)
    INSERT INTO inventory_logs (
        id, business_id, branch_id, product_id,
        old_quantity, new_quantity, change_amount,
        reason, actor_id, idempotency_key
    ) VALUES (
        gen_random_uuid(), v_business_id, p_branch_id, p_product_id,
        v_current_qty, v_current_qty + p_quantity, p_quantity,
        p_reason, auth.uid(), p_idempotency_key
    );
END;
$$;
