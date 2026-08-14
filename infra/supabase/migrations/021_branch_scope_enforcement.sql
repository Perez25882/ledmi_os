-- 021_branch_scope_enforcement.sql
-- Ship-readiness security audit remediation — Part 2 (branch scoping + write guards).
--   * RLS-H1: wire user_accessible_branches() into SELECT policies so branch-scoped
--             users (managers/cashiers) cannot read other branches of their business.
--   * RLS-M1: split the over-permissive FOR ALL policies on shifts/refunds.
--   * RLS-H2 / PAY-P4: a BEFORE INSERT trigger enforces that the acting user is
--             scoped to the branch they write to (carts/shifts/refunds), covering
--             every checkout/refund/shift RPC without rewriting their bodies. The
--             service-role webhook path (auth.uid() IS NULL) is exempt.
-- NULL branch access (owners/accountants) => user_accessible_branches returns all
-- branches, so those roles are unaffected. Idempotent; safe to re-run.

-- ============================================================
-- 1. Branch-scoped SELECT policies (RLS-H1)
-- ============================================================
DROP POLICY IF EXISTS "inventory_select" ON inventory;
CREATE POLICY "inventory_select" ON inventory
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND branch_id IN (SELECT user_accessible_branches(business_id))
);

DROP POLICY IF EXISTS "inventory_logs_select" ON inventory_logs;
CREATE POLICY "inventory_logs_select" ON inventory_logs
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND branch_id IN (SELECT user_accessible_branches(business_id))
);

-- activity_logs.branch_id is nullable (business-wide/system events); allow NULL.
DROP POLICY IF EXISTS "activity_logs_select" ON activity_logs;
CREATE POLICY "activity_logs_select" ON activity_logs
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND (branch_id IS NULL OR branch_id IN (SELECT user_accessible_branches(business_id)))
);

DROP POLICY IF EXISTS "invoices_select" ON invoices;
CREATE POLICY "invoices_select" ON invoices
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND branch_id IN (SELECT user_accessible_branches(business_id))
);

DROP POLICY IF EXISTS "sales_select" ON sales;
CREATE POLICY "sales_select" ON sales
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND branch_id IN (SELECT user_accessible_branches(business_id))
);

-- sale_items has no branch_id; scope through the parent sale.
DROP POLICY IF EXISTS "sale_items_select" ON sale_items;
CREATE POLICY "sale_items_select" ON sale_items
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM sales
        WHERE sales.id = sale_items.sale_id
        AND user_belongs_to_business(sales.business_id)
        AND sales.branch_id IN (SELECT user_accessible_branches(sales.business_id))
    )
);

-- carts: preserve the existing owner/manager/self visibility, add branch scope.
DROP POLICY IF EXISTS "carts_select" ON carts;
CREATE POLICY "carts_select" ON carts
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND branch_id IN (SELECT user_accessible_branches(business_id))
    AND (
        cashier_id = current_user_id()
        OR user_is_owner(business_id)
        OR user_has_permission(business_id, 'manage_users')
    )
);

-- ============================================================
-- 2. Split over-permissive shifts/refunds policies (RLS-M1)
--    The old FOR ALL policy let any business member PATCH another cashier's
--    shift (cash reconciliation) or INSERT refunds directly, bypassing the RPC.
-- ============================================================
DROP POLICY IF EXISTS shifts_business_access ON shifts;
CREATE POLICY shifts_select ON shifts FOR SELECT TO authenticated
    USING (
        user_belongs_to_business(business_id)
        AND branch_id IN (SELECT user_accessible_branches(business_id))
    );
CREATE POLICY shifts_insert_self ON shifts FOR INSERT TO authenticated
    WITH CHECK (
        user_belongs_to_business(business_id)
        AND cashier_id = current_user_id()
    );
CREATE POLICY shifts_update_self_or_manager ON shifts FOR UPDATE TO authenticated
    USING (
        user_belongs_to_business(business_id)
        AND (cashier_id = current_user_id() OR user_has_permission(business_id, 'manage_users'))
    )
    WITH CHECK (
        user_belongs_to_business(business_id)
        AND (cashier_id = current_user_id() OR user_has_permission(business_id, 'manage_users'))
    );

DROP POLICY IF EXISTS refunds_business_access ON refunds;
CREATE POLICY refunds_select ON refunds FOR SELECT TO authenticated
    USING (
        user_belongs_to_business(business_id)
        AND branch_id IN (SELECT user_accessible_branches(business_id))
    );
CREATE POLICY refunds_insert_self ON refunds FOR INSERT TO authenticated
    WITH CHECK (
        user_belongs_to_business(business_id)
        AND cashier_id = current_user_id()
    );
-- No general UPDATE/DELETE policy: refunds are append-only; corrections go
-- through the service role / a future void RPC.

-- ============================================================
-- 3. Branch-write enforcement trigger (RLS-H2 / PAY-P4)
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_branch_write()
RETURNS trigger AS $func$
BEGIN
    -- Service-role / internal calls (Paystack webhook finalization) have no
    -- auth.uid(); they are trusted and exempt.
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.branch_id IS NOT NULL
       AND NEW.branch_id NOT IN (SELECT user_accessible_branches(NEW.business_id)) THEN
        RAISE EXCEPTION 'User % not authorized for branch %', auth.uid(), NEW.branch_id;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_carts_branch_write ON carts;
CREATE TRIGGER trg_carts_branch_write
    BEFORE INSERT ON carts
    FOR EACH ROW EXECUTE FUNCTION enforce_branch_write();

DROP TRIGGER IF EXISTS trg_shifts_branch_write ON shifts;
CREATE TRIGGER trg_shifts_branch_write
    BEFORE INSERT ON shifts
    FOR EACH ROW EXECUTE FUNCTION enforce_branch_write();

DROP TRIGGER IF EXISTS trg_refunds_branch_write ON refunds;
CREATE TRIGGER trg_refunds_branch_write
    BEFORE INSERT ON refunds
    FOR EACH ROW EXECUTE FUNCTION enforce_branch_write();