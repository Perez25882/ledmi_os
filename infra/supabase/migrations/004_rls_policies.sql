-- 004_rls_policies.sql
-- LedgerMind OS MVP — Row Level Security policies.
--
-- * Enables RLS on every table created by 001_core_schema.sql and
--   002_branch_model.sql.
-- * Drops existing policies before recreating them so the migration is
--   idempotent.
-- * All access rules use helper functions from 003_auth_helpers.sql.
-- * Default posture is deny; only explicitly allowed rows/operations pass.

-- ============================================================
-- 1. Enable RLS on all tables
-- ============================================================

ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_business_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_processing_markers ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 2. Businesses
-- Owners can update; all members can view.
-- ============================================================

DROP POLICY IF EXISTS "businesses_select_members" ON businesses;
CREATE POLICY "businesses_select_members" ON businesses
FOR SELECT USING (user_belongs_to_business(id));

DROP POLICY IF EXISTS "businesses_update_owners" ON businesses;
CREATE POLICY "businesses_update_owners" ON businesses
FOR UPDATE USING (user_is_owner(id))
WITH CHECK (user_is_owner(id));


-- ============================================================
-- 3. Branches
-- Owners and managers (manage_users) can manage.
-- All members can view active, non-deleted branches.
-- ============================================================

DROP POLICY IF EXISTS "branches_select_active" ON branches;
CREATE POLICY "branches_select_active" ON branches
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND is_active = true
    AND deleted_at IS NULL
);

DROP POLICY IF EXISTS "branches_manage_owners_managers" ON branches;
CREATE POLICY "branches_manage_owners_managers" ON branches
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND (
        user_is_owner(business_id)
        OR user_has_permission(business_id, 'manage_users')
    )
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND (
        user_is_owner(business_id)
        OR user_has_permission(business_id, 'manage_users')
    )
);


-- ============================================================
-- 4. Custom Roles
-- Owners can manage.
-- Managers can view all roles in the business.
-- Members can view only their own assigned role.
-- ============================================================

DROP POLICY IF EXISTS "custom_roles_select" ON custom_roles;
CREATE POLICY "custom_roles_select" ON custom_roles
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND (
        user_is_owner(business_id)
        OR user_has_permission(business_id, 'manage_users')
        OR EXISTS (
            SELECT 1 FROM user_business_roles ubr
            WHERE ubr.role_id = custom_roles.id
            AND ubr.user_id = current_user_id()
        )
    )
);

DROP POLICY IF EXISTS "custom_roles_manage_owners" ON custom_roles;
CREATE POLICY "custom_roles_manage_owners" ON custom_roles
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND user_is_owner(business_id)
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_is_owner(business_id)
);


-- ============================================================
-- 5. User Business Roles
-- Owners can manage.
-- Managers can view all members.
-- Members can view their own row.
-- ============================================================

DROP POLICY IF EXISTS "user_business_roles_select" ON user_business_roles;
CREATE POLICY "user_business_roles_select" ON user_business_roles
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND (
        user_is_owner(business_id)
        OR user_has_permission(business_id, 'manage_users')
        OR user_id = current_user_id()
    )
);

DROP POLICY IF EXISTS "user_business_roles_manage_owners" ON user_business_roles;
CREATE POLICY "user_business_roles_manage_owners" ON user_business_roles
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND user_is_owner(business_id)
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_is_owner(business_id)
);


-- ============================================================
-- 6. Categories
-- All members read; managers/owners write.
-- ============================================================

DROP POLICY IF EXISTS "categories_select" ON categories;
CREATE POLICY "categories_select" ON categories
FOR SELECT USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS "categories_write_managers" ON categories;
CREATE POLICY "categories_write_managers" ON categories
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_products')
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_products')
);


-- ============================================================
-- 7. Suppliers
-- All members read; managers/owners write (manage_inventory).
-- ============================================================

DROP POLICY IF EXISTS "suppliers_select" ON suppliers;
CREATE POLICY "suppliers_select" ON suppliers
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND deleted_at IS NULL
);

DROP POLICY IF EXISTS "suppliers_write_managers" ON suppliers;
CREATE POLICY "suppliers_write_managers" ON suppliers
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_inventory')
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_inventory')
);


-- ============================================================
-- 8. Products
-- All members read; managers/owners write.
-- ============================================================

DROP POLICY IF EXISTS "products_select" ON products;
CREATE POLICY "products_select" ON products
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND deleted_at IS NULL
);

DROP POLICY IF EXISTS "products_write_managers" ON products;
CREATE POLICY "products_write_managers" ON products
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_products')
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_products')
);


-- ============================================================
-- 9. Inventory
-- All members read.
-- Managers/owners can insert/update (manage_inventory).
-- Cashiers never update inventory directly; no user deletes.
-- ============================================================

DROP POLICY IF EXISTS "inventory_select" ON inventory;
CREATE POLICY "inventory_select" ON inventory
FOR SELECT USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS "inventory_insert_managers" ON inventory;
CREATE POLICY "inventory_insert_managers" ON inventory
FOR INSERT WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_inventory')
);

DROP POLICY IF EXISTS "inventory_update_managers" ON inventory;
CREATE POLICY "inventory_update_managers" ON inventory
FOR UPDATE USING (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_inventory')
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'manage_inventory')
);


-- ============================================================
-- 10. Inventory Logs
-- All members read; never update/delete.
-- ============================================================

DROP POLICY IF EXISTS "inventory_logs_select" ON inventory_logs;
CREATE POLICY "inventory_logs_select" ON inventory_logs
FOR SELECT USING (user_belongs_to_business(business_id));


-- ============================================================
-- 11. Activity Logs
-- All members read; system append-only.
-- ============================================================

DROP POLICY IF EXISTS "activity_logs_select" ON activity_logs;
CREATE POLICY "activity_logs_select" ON activity_logs
FOR SELECT USING (user_belongs_to_business(business_id));


-- ============================================================
-- 12. Carts
-- Cashier owns their carts.
-- Managers/owners can view all carts in the business.
-- ============================================================

DROP POLICY IF EXISTS "carts_select" ON carts;
CREATE POLICY "carts_select" ON carts
FOR SELECT USING (
    user_belongs_to_business(business_id)
    AND (
        cashier_id = current_user_id()
        OR user_is_owner(business_id)
        OR user_has_permission(business_id, 'manage_users')
    )
);

DROP POLICY IF EXISTS "carts_write_cashier" ON carts;
CREATE POLICY "carts_write_cashier" ON carts
FOR ALL USING (
    user_belongs_to_business(business_id)
    AND cashier_id = current_user_id()
    AND user_has_permission(business_id, 'process_sales')
)
WITH CHECK (
    user_belongs_to_business(business_id)
    AND cashier_id = current_user_id()
    AND user_has_permission(business_id, 'process_sales')
);


-- ============================================================
-- 13. Cart Items
-- Scoped through cart ownership.
-- Cashiers can only modify items in their own carts.
-- Managers/owners can view items in any cart in the business.
-- ============================================================

DROP POLICY IF EXISTS "cart_items_select" ON cart_items;
CREATE POLICY "cart_items_select" ON cart_items
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM carts
        WHERE carts.id = cart_items.cart_id
        AND user_belongs_to_business(carts.business_id)
        AND (
            carts.cashier_id = current_user_id()
            OR user_is_owner(carts.business_id)
            OR user_has_permission(carts.business_id, 'manage_users')
        )
    )
);

DROP POLICY IF EXISTS "cart_items_write_cashier" ON cart_items;
CREATE POLICY "cart_items_write_cashier" ON cart_items
FOR ALL USING (
    EXISTS (
        SELECT 1 FROM carts
        WHERE carts.id = cart_items.cart_id
        AND user_belongs_to_business(carts.business_id)
        AND carts.cashier_id = current_user_id()
        AND user_has_permission(carts.business_id, 'process_sales')
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM carts
        WHERE carts.id = cart_items.cart_id
        AND user_belongs_to_business(carts.business_id)
        AND carts.cashier_id = current_user_id()
        AND user_has_permission(carts.business_id, 'process_sales')
    )
);


-- ============================================================
-- 14. Payments
-- All members read; cashiers insert for their business.
-- Immutable once created: no update/delete by users.
-- ============================================================

DROP POLICY IF EXISTS "payments_select" ON payments;
CREATE POLICY "payments_select" ON payments
FOR SELECT USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS "payments_insert_cashiers" ON payments;
CREATE POLICY "payments_insert_cashiers" ON payments
FOR INSERT WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'process_sales')
);


-- ============================================================
-- 15. Invoices
-- All members read; cashiers insert for their business.
-- ============================================================

DROP POLICY IF EXISTS "invoices_select" ON invoices;
CREATE POLICY "invoices_select" ON invoices
FOR SELECT USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS "invoices_insert_cashiers" ON invoices;
CREATE POLICY "invoices_insert_cashiers" ON invoices
FOR INSERT WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'process_sales')
);


-- ============================================================
-- 16. Sales
-- All members read; cashiers insert for their business.
-- ============================================================

DROP POLICY IF EXISTS "sales_select" ON sales;
CREATE POLICY "sales_select" ON sales
FOR SELECT USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS "sales_insert_cashiers" ON sales;
CREATE POLICY "sales_insert_cashiers" ON sales
FOR INSERT WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'process_sales')
);


-- ============================================================
-- 17. Sale Items
-- Read through parent sale; insert with process_sales permission.
-- ============================================================

DROP POLICY IF EXISTS "sale_items_select" ON sale_items;
CREATE POLICY "sale_items_select" ON sale_items
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM sales
        WHERE sales.id = sale_items.sale_id
        AND user_belongs_to_business(sales.business_id)
    )
);

DROP POLICY IF EXISTS "sale_items_insert_cashiers" ON sale_items;
CREATE POLICY "sale_items_insert_cashiers" ON sale_items
FOR INSERT WITH CHECK (
    EXISTS (
        SELECT 1 FROM sales
        WHERE sales.id = sale_items.sale_id
        AND user_belongs_to_business(sales.business_id)
        AND user_has_permission(sales.business_id, 'process_sales')
    )
);


-- ============================================================
-- 18. Payment Intents
-- All members read; cashiers insert for their business.
-- ============================================================

DROP POLICY IF EXISTS "payment_intents_select" ON payment_intents;
CREATE POLICY "payment_intents_select" ON payment_intents
FOR SELECT USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS "payment_intents_insert_cashiers" ON payment_intents;
CREATE POLICY "payment_intents_insert_cashiers" ON payment_intents
FOR INSERT WITH CHECK (
    user_belongs_to_business(business_id)
    AND user_has_permission(business_id, 'process_sales')
);


-- ============================================================
-- 19. Payment Events
-- Read only for owner / manager / accountant (view_reports).
-- Edge Functions / service role append events.
-- ============================================================

DROP POLICY IF EXISTS "payment_events_select_finance" ON payment_events;
CREATE POLICY "payment_events_select_finance" ON payment_events
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM payment_intents
        WHERE payment_intents.id = payment_events.payment_intent_id
        AND (
            user_is_owner(payment_intents.business_id)
            OR user_has_permission(payment_intents.business_id, 'view_reports')
        )
    )
);


-- ============================================================
-- 20. Webhook Receipts
-- Read only for owner / manager / accountant (view_reports).
-- No user insert/update/delete: Edge Function uses service role.
--
-- Note: webhook_receipts has no business_id column. The policy
-- scopes read access to users with view_reports in their currently
-- selected JWT business. Business-scoped reporting views/RPCs are
-- recommended for cross-business webhook lookup.
-- ============================================================

DROP POLICY IF EXISTS "webhook_receipts_select_finance" ON webhook_receipts;
CREATE POLICY "webhook_receipts_select_finance" ON webhook_receipts
FOR SELECT USING (
    user_has_permission(current_business_id(), 'view_reports')
);


-- ============================================================
-- 21. Payment Processing Markers
-- Read only for owner / manager (view_reports).
-- Edge Function / service role manages markers.
-- ============================================================

DROP POLICY IF EXISTS "payment_processing_markers_select_managers" ON payment_processing_markers;
CREATE POLICY "payment_processing_markers_select_managers" ON payment_processing_markers
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM payment_intents
        WHERE payment_intents.id = payment_processing_markers.payment_intent_id
        AND (
            user_is_owner(payment_intents.business_id)
            OR user_has_permission(payment_intents.business_id, 'view_reports')
        )
    )
);
