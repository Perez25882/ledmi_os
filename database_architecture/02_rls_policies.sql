-- 02_rls_policies.sql
-- Unified Retail OS - Row Level Security (RLS)

-- ============================================================
-- 1. Enable RLS on ALL tables (DENY BY DEFAULT)
-- ============================================================

-- Legacy tables
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
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

-- New payment event-sourced tables
ALTER TABLE payment_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_processing_markers ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. Helper Functions
-- SECURITY DEFINER is used so they can run with elevated
-- privileges while strictly verifying auth.uid()
-- ============================================================

CREATE OR REPLACE FUNCTION user_belongs_to_business(target_business_id UUID)
RETURNS BOOLEAN AS $$BEGIN
    -- SECURITY FIX: Return false for anonymous users instead of NULL
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles
        WHERE user_id = auth.uid()
        AND business_id = target_business_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION user_has_permission(target_business_id UUID, required_permission TEXT)
RETURNS BOOLEAN AS $$BEGIN
    -- SECURITY FIX: Return false for anonymous users instead of NULL
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles ubr
        JOIN custom_roles cr ON ubr.role_id = cr.id
        WHERE ubr.user_id = auth.uid()
        AND ubr.business_id = target_business_id
        AND cr.permissions ? required_permission
        AND (cr.permissions ->> required_permission)::boolean = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION user_is_owner(target_business_id UUID)
RETURNS BOOLEAN AS $$BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles ubr
        JOIN custom_roles cr ON ubr.role_id = cr.id
        WHERE ubr.user_id = auth.uid()
        AND ubr.business_id = target_business_id
        AND cr.name = 'owner'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. Legacy Table Policies
-- ============================================================

-- Businesses: view own, update if owner. No DELETE.
CREATE POLICY "Users can view businesses they belong to" ON businesses
FOR SELECT USING (user_belongs_to_business(id));

CREATE POLICY "Owners can update their business" ON businesses
FOR UPDATE USING (user_is_owner(id));

-- Roles: view own, manage if admin
CREATE POLICY "View business roles" ON custom_roles
FOR SELECT USING (user_belongs_to_business(business_id));

CREATE POLICY "Admin manage roles" ON custom_roles
FOR ALL USING (user_has_permission(business_id, 'manage_roles'));

-- User-Business Roles: view own, manage if admin
CREATE POLICY "View business members" ON user_business_roles
FOR SELECT USING (user_belongs_to_business(business_id));

CREATE POLICY "Admin manage members" ON user_business_roles
FOR ALL USING (user_has_permission(business_id, 'manage_roles'));

-- Products, Categories, Suppliers
CREATE POLICY "Staff read products" ON products FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Manager write products" ON products
FOR ALL USING (user_has_permission(business_id, 'manage_products'));

CREATE POLICY "Staff read categories" ON categories FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Manager write categories" ON categories
FOR ALL USING (user_has_permission(business_id, 'manage_products'));

CREATE POLICY "Staff read suppliers" ON suppliers FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Manager write suppliers" ON suppliers
FOR ALL USING (user_has_permission(business_id, 'manage_inventory'));

-- Inventory
CREATE POLICY "Staff read inventory" ON inventory FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Manager update inventory" ON inventory
FOR ALL USING (user_has_permission(business_id, 'manage_inventory'));

-- Inventory Logs: read only, no update/delete
CREATE POLICY "Staff read inventory logs" ON inventory_logs FOR SELECT USING (user_belongs_to_business(business_id));

-- Activity Logs: read only, no update/delete
CREATE POLICY "Staff read activity logs" ON activity_logs FOR SELECT USING (user_belongs_to_business(business_id));

-- Carts: own or permission
CREATE POLICY "Users manage own carts" ON carts
FOR ALL USING (user_belongs_to_business(business_id) AND (cashier_id = auth.uid() OR user_has_permission(business_id, 'process_sales')));

-- Cart Items: scoped via carts
CREATE POLICY "Users manage cart items" ON cart_items
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM carts
    WHERE carts.id = cart_items.cart_id
    AND user_belongs_to_business(carts.business_id)
    AND (carts.cashier_id = auth.uid() OR user_has_permission(carts.business_id, 'process_sales'))
  )
);

-- Payments
CREATE POLICY "Staff read payments" ON payments FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Cashier insert payments" ON payments
FOR INSERT WITH CHECK (user_belongs_to_business(business_id) AND user_has_permission(business_id, 'process_sales'));

-- Invoices
CREATE POLICY "Staff read invoices" ON invoices FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Cashier insert invoices" ON invoices
FOR INSERT WITH CHECK (user_belongs_to_business(business_id) AND user_has_permission(business_id, 'process_sales'));

-- Sales
CREATE POLICY "Cashier read sales" ON sales FOR SELECT USING (user_belongs_to_business(business_id));
CREATE POLICY "Cashier insert sales" ON sales
FOR INSERT WITH CHECK (user_belongs_to_business(business_id) AND user_has_permission(business_id, 'process_sales'));

-- Sale Items
CREATE POLICY "Cashier read sale items" ON sale_items FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM sales
    WHERE sales.id = sale_items.sale_id
    AND user_belongs_to_business(sales.business_id)
  )
);
CREATE POLICY "Cashier insert sale items" ON sale_items
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM sales
    WHERE sales.id = sale_items.sale_id
    AND user_belongs_to_business(sales.business_id)
    AND user_has_permission(sales.business_id, 'process_sales')
  )
);

-- ============================================================
-- 4. Event-Sourced Payment Policies
-- ============================================================

-- payment_intents
CREATE POLICY "Staff read payment intents" ON payment_intents
FOR SELECT USING (user_belongs_to_business(business_id));

CREATE POLICY "Cashier create payment intents" ON payment_intents
FOR INSERT WITH CHECK (user_belongs_to_business(business_id) AND user_has_permission(business_id, 'process_sales'));

-- payment_events: read only, no modify
CREATE POLICY "Staff read payment events" ON payment_events
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM payment_intents
        WHERE payment_intents.id = payment_events.payment_intent_id
        AND user_belongs_to_business(payment_intents.business_id)
    )
);

-- webhook_receipts: deny all for normal users
CREATE POLICY "Deny webhook_receipts access" ON webhook_receipts FOR ALL USING (false);

-- payment_processing_markers: read only
CREATE POLICY "Staff read payment markers" ON payment_processing_markers
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM payment_intents
        WHERE payment_intents.id = payment_processing_markers.payment_intent_id
        AND user_belongs_to_business(payment_intents.business_id)
    )
);
