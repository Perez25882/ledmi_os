-- 020_security_hardening.sql
-- Ship-readiness security audit remediation — Part 1 (anon-exploitable holes).
-- Closes cross-tenant leaks and sale-forgery reachable with the PUBLIC anon key.
-- Idempotent. Safe to re-run.

-- ============================================================
-- 1. Lock down aggregation matviews + snapshot view (audit RLS-C2/C3)
--    Materialized views cannot carry RLS. A plain view without
--    security_invoker evaluates underlying RLS as its (BYPASSRLS) owner.
--    Supabase's default privileges had granted anon + authenticated full
--    access, so any holder of the public anon key could read every tenant's
--    sales, stock velocity, cost price and margins via PostgREST directly.
--    Reads are moved to the service-role layer (see lib/supabase/data/insights.ts).
-- ============================================================
REVOKE ALL ON mv_daily_sales       FROM anon, authenticated;
REVOKE ALL ON mv_stock_velocity    FROM anon, authenticated;
REVOKE ALL ON v_inventory_snapshot FROM anon, authenticated;

-- Defense in depth: force the plain view to evaluate RLS as the querying user.
ALTER VIEW v_inventory_snapshot SET (security_invoker = true);

-- ============================================================
-- 2. Restrict webhook-internal SECURITY DEFINER functions (audit RLS-C4)
--    safe_finalize_sale and process_payment_capture are only ever invoked by
--    the Paystack webhook Edge Function using the service-role key. The
--    Postgres/Supabase default of EXECUTE TO PUBLIC let any anon/authenticated
--    caller forge a finalized sale (decrement inventory, fabricate a payment)
--    by passing another business's payment_intent_id. Restrict to service_role.
-- ============================================================
REVOKE EXECUTE ON FUNCTION safe_finalize_sale(UUID)              FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION process_payment_capture(UUID, UUID)   FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION safe_finalize_sale(UUID)              TO service_role;
GRANT  EXECUTE ON FUNCTION process_payment_capture(UUID, UUID)   TO service_role;

-- ============================================================
-- 3. Harden process_stock_in (audit RLS-C1)
--    Previously SECURITY DEFINER with NO authorization: it derived business_id
--    from the caller-supplied branch and trusted it, letting any user (or anon)
--    inject/overwrite another business's inventory and forge inventory_logs.
--    Add membership + manage_inventory permission + branch-assignment checks.
--    Managers legitimately receive stock, so keep authenticated EXECUTE but
--    revoke anon entirely.
-- ============================================================
CREATE OR REPLACE FUNCTION process_stock_in(
    p_branch_id       UUID,
    p_product_id      UUID,
    p_quantity        INT,
    p_reason          TEXT DEFAULT 'delivery',
    p_idempotency_key TEXT DEFAULT gen_random_uuid()::text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $func$
DECLARE
    v_business_id  UUID;
    v_current_qty  INT;
BEGIN
    SELECT business_id INTO v_business_id
    FROM branches WHERE id = p_branch_id AND deleted_at IS NULL;
    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Branch not found';
    END IF;

    -- Authorization: caller must belong to the business, hold manage_inventory,
    -- and be scoped to this branch (owners/accountants see all branches).
    IF NOT user_belongs_to_business(v_business_id) THEN
        RAISE EXCEPTION 'User does not belong to business';
    END IF;
    IF NOT user_has_permission(v_business_id, 'manage_inventory') THEN
        RAISE EXCEPTION 'Missing manage_inventory permission';
    END IF;
    IF p_branch_id NOT IN (SELECT user_accessible_branches(v_business_id)) THEN
        RAISE EXCEPTION 'User not authorized for this branch';
    END IF;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive';
    END IF;

    -- Idempotency: skip if this key was already processed.
    IF EXISTS (SELECT 1 FROM inventory_logs WHERE idempotency_key = p_idempotency_key) THEN
        RETURN;
    END IF;

    SELECT quantity INTO v_current_qty
    FROM inventory WHERE product_id = p_product_id AND branch_id = p_branch_id;

    IF v_current_qty IS NULL THEN
        INSERT INTO inventory (product_id, branch_id, business_id, quantity, reorder_level)
        VALUES (p_product_id, p_branch_id, v_business_id, p_quantity, 5);
        v_current_qty := 0;
    ELSE
        UPDATE inventory
        SET quantity = v_current_qty + p_quantity, updated_at = now()
        WHERE product_id = p_product_id AND branch_id = p_branch_id;
    END IF;

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
$func$;

REVOKE EXECUTE ON FUNCTION process_stock_in(UUID, UUID, INT, TEXT, TEXT) FROM anon;
GRANT  EXECUTE ON FUNCTION process_stock_in(UUID, UUID, INT, TEXT, TEXT) TO authenticated;