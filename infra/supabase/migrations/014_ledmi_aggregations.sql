-- 014_ledmi_aggregations.sql
-- LedgerMind OS MVP — Ledmi AI aggregation layer (DEPT_AI_STATUS §3 gap #2).
-- Implements LEDMI_DESIGN §2.2: mv_daily_sales, mv_stock_velocity (feature store),
-- v_inventory_snapshot, plus a concurrent-refresh function and a guarded pg_cron job.
--
-- Notes:
--   * Idempotent: CREATE MATERIALIZED VIEW IF NOT EXISTS, CREATE OR REPLACE VIEW,
--     CREATE UNIQUE INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION, DO blocks.
--   * No forward-refs: depends only on tables finalized in 001 + 002 (+ 010 reorder_level).
--   * CONCURRENTLY refresh requires the unique indexes created below.
--   * pg_cron registration is guarded so the migration is safe when the extension
--     is absent (e.g. local Supabase without cron). External-scheduler fallback:
--     call refresh_ledmi_aggregations() daily at 06:00 GMT from a Supabase Edge
--     Function (cron.trigger) or any external scheduler with the service role key.


-- ============================================================
-- 1. mv_daily_sales — branch-day revenue/traffic rollup
-- ============================================================
-- Aggregates finalized sales by business_id, branch_id, sale date:
--   total_revenue    = SUM(sale_items.subtotal)
--   sales_count      = COUNT(DISTINCT sales.id)
--   items_sold       = SUM(sale_items.quantity)
--   avg_basket_value = total_revenue / sales_count

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_sales AS
SELECT
    s.business_id,
    s.branch_id,
    DATE(s.created_at) AS sale_date,
    SUM(si.subtotal) AS total_revenue,
    COUNT(DISTINCT s.id) AS sales_count,
    SUM(si.quantity) AS items_sold,
    CASE WHEN COUNT(DISTINCT s.id) > 0
         THEN SUM(si.subtotal) / COUNT(DISTINCT s.id)
         ELSE 0
    END AS avg_basket_value
FROM sales s
JOIN sale_items si ON si.sale_id = s.id
GROUP BY s.business_id, s.branch_id, DATE(s.created_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_sales_uq
    ON mv_daily_sales (business_id, branch_id, sale_date);

CREATE INDEX IF NOT EXISTS idx_mv_daily_sales_lookup
    ON mv_daily_sales (business_id, branch_id, sale_date);


-- ============================================================
-- 2. mv_stock_velocity — per-SKU per-branch feature store (rolling 30d)
-- ============================================================
-- Computes sales velocity directly from sale_items joined to sales over the
-- last 30 days, then joins inventory for current stock and days_until_stockout:
--   avg_daily_units     = AVG(units_sold_per_day) over days with sales
--   stddev_daily_units  = STDDEV(units_sold_per_day)
--   days_until_stockout = current_stock / avg_daily_units (NULL when no velocity)
--   last_sale_date      = MAX(sale_date)

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_stock_velocity AS
WITH daily_units AS (
    SELECT
        s.business_id,
        s.branch_id,
        si.product_id,
        DATE(s.created_at) AS sale_date,
        SUM(si.quantity) AS units_sold
    FROM sales s
    JOIN sale_items si ON si.sale_id = s.id
    WHERE s.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY s.business_id, s.branch_id, si.product_id, DATE(s.created_at)
),
velocity AS (
    SELECT
        business_id,
        branch_id,
        product_id,
        SUM(units_sold) AS total_units_30d,
        AVG(units_sold) AS avg_daily_units,
        STDDEV(units_sold) AS stddev_daily_units,
        COUNT(DISTINCT sale_date) AS days_with_sales,
        MAX(sale_date) AS last_sale_date
    FROM daily_units
    GROUP BY business_id, branch_id, product_id
)
SELECT
    v.business_id,
    v.branch_id,
    v.product_id,
    p.name AS product_name,
    p.sku,
    i.quantity AS current_stock,
    i.reorder_level,
    v.total_units_30d,
    ROUND(v.avg_daily_units::numeric, 3) AS avg_daily_units,
    ROUND(COALESCE(v.stddev_daily_units, 0)::numeric, 3) AS stddev_daily_units,
    v.days_with_sales,
    CASE
        WHEN v.avg_daily_units > 0 THEN ROUND((i.quantity / v.avg_daily_units)::numeric, 1)
        ELSE NULL
    END AS days_until_stockout,
    v.last_sale_date,
    NOW() AS computed_at
FROM velocity v
JOIN products p ON p.id = v.product_id
JOIN inventory i ON i.product_id = v.product_id AND i.branch_id = v.branch_id
WHERE p.deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_stock_velocity_uq
    ON mv_stock_velocity (business_id, branch_id, product_id);

CREATE INDEX IF NOT EXISTS idx_mv_stock_velocity_stockout
    ON mv_stock_velocity (business_id, days_until_stockout)
    WHERE days_until_stockout IS NOT NULL AND days_until_stockout <= 7;


-- ============================================================
-- 3. v_inventory_snapshot — read-only current-stock convenience view
-- ============================================================

CREATE OR REPLACE VIEW v_inventory_snapshot AS
SELECT
    i.business_id,
    i.branch_id,
    b.name AS branch_name,
    i.product_id,
    p.name AS product_name,
    p.sku,
    p.barcode,
    p.selling_price,
    p.cost_price,
    p.supplier_id,
    p.reorder_threshold,
    i.reorder_level,
    i.quantity AS current_stock,
    (p.selling_price - p.cost_price) AS unit_margin,
    (p.selling_price - p.cost_price) * i.quantity AS stock_value_margin
FROM inventory i
JOIN products p ON p.id = i.product_id
JOIN branches b ON b.id = i.branch_id
WHERE p.deleted_at IS NULL AND b.deleted_at IS NULL;


-- ============================================================
-- 4. refresh_ledmi_aggregations() — concurrent refresh entrypoint
-- ============================================================
-- SECURITY DEFINER so an external scheduler / post-sync trigger can call it
-- without needing ownership of the materialized views. Idempotent.

CREATE OR REPLACE FUNCTION refresh_ledmi_aggregations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_stock_velocity;
END;
$$;


-- ============================================================
-- 5. pg_cron registration (guarded) — daily 06:00 GMT refresh
-- ============================================================
-- Registers 'ledmi_daily_refresh' only if pg_cron is installed.
-- Fallback when pg_cron is absent: invoke refresh_ledmi_aggregations() from a
-- Supabase Edge Function scheduled via cron.trigger, or any external scheduler
-- at 06:00 GMT using the service role key.

DO $cron_block$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- unschedule any prior version of the job (idempotent re-registration)
        PERFORM cron.unschedule('ledmi_daily_refresh');
        PERFORM cron.schedule(
            'ledmi_daily_refresh',
            '0 6 * * *',
            $cmd$SELECT refresh_ledmi_aggregations();$cmd$
        );
    END IF;
END;
$cron_block$;
