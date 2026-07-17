-- FILE: 001_core_schema.sql

-- 001_core_schema.sql
-- LedgerMind OS MVP — Core multi-tenant schema.
-- Creates: businesses, custom_roles, user_business_roles, categories,
-- suppliers, products, inventory, inventory_logs, payments (legacy),
-- carts, cart_items, invoices, sales, sale_items, activity_logs,
-- payment_intents, payment_events, webhook_receipts, payment_processing_markers.
--
-- Notes:
--   * Idempotent: uses CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
--     and DROP TRIGGER IF EXISTS / CREATE TRIGGER for updated_at triggers.
--   * RLS policies are intentionally excluded; see 003_auth_helpers.sql and
--     004_rls_policies.sql (Security agent).
--   * Paystack-specific RPC lives in 005_paystack_rpc.sql (Payment agent).
--   * The legacy `payments` table is preserved unchanged for backward compatibility.


-- ============================================================
-- Extensions
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ============================================================
-- 1. Businesses
-- ============================================================

CREATE TABLE IF NOT EXISTS businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_businesses_active ON businesses(id) WHERE deleted_at IS NULL;


-- ============================================================
-- 2. Custom Roles (RBAC per business)
-- ============================================================

CREATE TABLE IF NOT EXISTS custom_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(50) NOT NULL,
    permissions JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(business_id, name)
);

CREATE INDEX IF NOT EXISTS idx_custom_roles_business ON custom_roles(business_id);


-- ============================================================
-- 3. User Business Roles mapping
-- ============================================================

CREATE TABLE IF NOT EXISTS user_business_roles (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES custom_roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY(user_id, business_id)
);

CREATE INDEX IF NOT EXISTS idx_user_business_roles_business ON user_business_roles(business_id);


-- ============================================================
-- 4. Categories
-- ============================================================

CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(business_id, name)
);

CREATE INDEX IF NOT EXISTS idx_categories_business ON categories(business_id);


-- ============================================================
-- 5. Suppliers
-- ============================================================

CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_suppliers_business ON suppliers(business_id);


-- ============================================================
-- 6. Products
-- ============================================================

CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100),
    barcode VARCHAR(100),
    selling_price DECIMAL(12, 2) NOT NULL CHECK (selling_price >= 0),
    cost_price DECIMAL(12, 2) NOT NULL CHECK (cost_price >= 0),
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    reorder_threshold INT DEFAULT 10,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(business_id, barcode),
    UNIQUE(business_id, sku)
);

CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(business_id, barcode);
CREATE INDEX IF NOT EXISTS idx_products_business ON products(business_id);
CREATE INDEX IF NOT EXISTS idx_products_deleted ON products(business_id) WHERE deleted_at IS NULL;


-- ============================================================
-- 7. Inventory
-- ============================================================

CREATE TABLE IF NOT EXISTS inventory (
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    quantity INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT pk_inventory PRIMARY KEY(product_id, business_id)
);

CREATE INDEX IF NOT EXISTS idx_inventory_business ON inventory(business_id);


-- ============================================================
-- 8. Inventory Logs (Immutable audit trail)
-- ============================================================

CREATE TABLE IF NOT EXISTS inventory_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    old_quantity INT NOT NULL,
    new_quantity INT NOT NULL,
    change_amount INT NOT NULL,
    reason VARCHAR(255) NOT NULL,
    actor_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_logs_business ON inventory_logs(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_logs_product ON inventory_logs(product_id);


-- ============================================================
-- 9. Payments (Legacy)
-- PCI Compliant, No full CC details, No CVV.
-- Kept unchanged for backward compatibility with existing checkout flows.
-- ============================================================

CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    cashier_id UUID NOT NULL REFERENCES auth.users(id),
    method VARCHAR(50) NOT NULL,
    amount DECIMAL(12, 2) NOT NULL CHECK (amount >= 0),
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    provider_reference VARCHAR(255),
    card_last4 VARCHAR(4),
    card_brand VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_business ON payments(business_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_provider ON payments(provider_reference) WHERE provider_reference IS NOT NULL;


-- ============================================================
-- 10. Carts (Temporary POS Session)
-- ============================================================

CREATE TABLE IF NOT EXISTS carts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    cashier_id UUID NOT NULL REFERENCES auth.users(id),
    status VARCHAR(50) DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_carts_business ON carts(business_id);
CREATE INDEX IF NOT EXISTS idx_carts_cashier ON carts(cashier_id);
CREATE INDEX IF NOT EXISTS idx_carts_status ON carts(status);


-- ============================================================
-- 11. Cart Items
-- ============================================================

CREATE TABLE IF NOT EXISTS cart_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cart_id UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(12, 2) NOT NULL CHECK (unit_price >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cart_items_cart ON cart_items(cart_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product ON cart_items(product_id);


-- ============================================================
-- 12. Invoices
-- ============================================================

CREATE TABLE IF NOT EXISTS invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    invoice_number VARCHAR(100) NOT NULL,
    cashier_id UUID NOT NULL REFERENCES auth.users(id),
    payment_id UUID NOT NULL REFERENCES payments(id),
    subtotal DECIMAL(12, 2) NOT NULL CHECK (subtotal >= 0),
    tax DECIMAL(12, 2) DEFAULT 0 CHECK (tax >= 0),
    total DECIMAL(12, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(business_id, invoice_number)
);

CREATE INDEX IF NOT EXISTS idx_invoices_business ON invoices(business_id);
CREATE INDEX IF NOT EXISTS idx_invoices_payment ON invoices(payment_id);


-- ============================================================
-- 13. Sales / Finalized Sale Data
-- ============================================================

CREATE TABLE IF NOT EXISTS sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES invoices(id),
    payment_id UUID NOT NULL REFERENCES payments(id),
    cashier_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sales_business ON sales(business_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice ON sales(invoice_id);
CREATE INDEX IF NOT EXISTS idx_sales_payment ON sales(payment_id);


-- ============================================================
-- 14. Sale Items
-- ============================================================

CREATE TABLE IF NOT EXISTS sale_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(12, 2) NOT NULL CHECK (unit_price >= 0),
    subtotal DECIMAL(12, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id);


-- ============================================================
-- 15. Activity Logs (Non-inventory audit)
-- ============================================================

CREATE TABLE IF NOT EXISTS activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id),
    action VARCHAR(255) NOT NULL,
    entity_table VARCHAR(100),
    entity_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_logs_business ON activity_logs(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_actor ON activity_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_metadata ON activity_logs USING GIN(metadata jsonb_path_ops);


-- ============================================================
-- EVENT-SOURCED PAYMENT ARCHITECTURE
-- ============================================================
--
-- Tables:
--   payment_intents              -> Business request to collect money
--   payment_events               -> Immutable event ledger (source of truth)
--   webhook_receipts             -> Audit trail for all incoming webhooks
--   payment_processing_markers   -> Prevents duplicate side-effects
--
-- Legacy compatibility:
--   * The `payments` table above is kept entirely unchanged.
--   * Payment projection / capture logic lives in 005_paystack_rpc.sql.
-- ============================================================

-- Payment Intents: Business request to collect money.
-- STATUS COLUMN IS A PROJECTION ONLY.
-- True source of truth is the payment_events ledger.
CREATE TABLE IF NOT EXISTS payment_intents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    cart_id UUID REFERENCES carts(id) ON DELETE SET NULL,
    invoice_id UUID,
    customer_reference VARCHAR(255),
    amount DECIMAL(12, 2) NOT NULL CHECK (amount >= 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'GHS',
    idempotency_key UUID NOT NULL,
    provider VARCHAR(50) NOT NULL DEFAULT 'paystack',
    provider_reference VARCHAR(255),
    status VARCHAR(50) NOT NULL DEFAULT 'initiated',
    legacy_payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_payment_intents_idempotency UNIQUE (idempotency_key),
    CONSTRAINT chk_payment_intents_amount CHECK (amount >= 0),
    CONSTRAINT chk_payment_intents_status CHECK (status IN ('initiated', 'pending', 'completed', 'failed', 'refunded', 'disputed'))
);

CREATE INDEX IF NOT EXISTS idx_payment_intents_idempotency ON payment_intents(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_payment_intents_business ON payment_intents(business_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_cart ON payment_intents(cart_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_legacy_payment ON payment_intents(legacy_payment_id);

-- Payment Events: Immutable financial history.
-- Append only. Never update. Never delete.
CREATE TABLE IF NOT EXISTS payment_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_intent_id UUID NOT NULL REFERENCES payment_intents(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    provider VARCHAR(50) NOT NULL,
    provider_event_id VARCHAR(255),
    provider_reference VARCHAR(255),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payment_events_type CHECK (event_type IN (
        'payment_initiated', 'payment_authorized', 'payment_captured',
        'payment_failed', 'payment_refunded', 'payment_partially_refunded',
        'chargeback_created', 'chargeback_won', 'chargeback_lost',
        'payment_cancelled', 'webhook_received'
    ))
);

CREATE INDEX IF NOT EXISTS idx_payment_events_intent ON payment_events(payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_events_intent_occurred ON payment_events(payment_intent_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_payment_events_provider_ref ON payment_events(provider_reference);
CREATE INDEX IF NOT EXISTS idx_payment_events_occurred ON payment_events(occurred_at);

-- Unique constraint for event deduplication.
-- Note: NULL != NULL in unique indexes, so system-generated events
-- (no provider_event_id) can be freely inserted without conflict.
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_events_provider_event
ON payment_events(provider, provider_event_id)
WHERE provider_event_id IS NOT NULL;

-- Webhook Receipts: Audit trail for all received webhooks.
CREATE TABLE IF NOT EXISTS webhook_receipts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider VARCHAR(50) NOT NULL,
    provider_event_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    signature_valid BOOLEAN NOT NULL DEFAULT false,
    payload_hash VARCHAR(64) NOT NULL,
    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_webhook_receipts_provider_event UNIQUE (provider, provider_event_id, event_type)
);

CREATE INDEX IF NOT EXISTS idx_webhook_receipts_provider ON webhook_receipts(provider, provider_event_id);
CREATE INDEX IF NOT EXISTS idx_webhook_receipts_received ON webhook_receipts(received_at);

-- Payment Processing Markers: Prevents duplicate side-effects.
CREATE TABLE IF NOT EXISTS payment_processing_markers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_intent_id UUID NOT NULL REFERENCES payment_intents(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES payment_events(id) ON DELETE CASCADE,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_payment_marker_intent UNIQUE (payment_intent_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_markers_intent ON payment_processing_markers(payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_markers_event ON payment_processing_markers(event_id);


-- ============================================================
-- Updated-at trigger helper and table triggers
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $func$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at_businesses ON businesses;
CREATE TRIGGER set_updated_at_businesses
    BEFORE UPDATE ON businesses FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_custom_roles ON custom_roles;
CREATE TRIGGER set_updated_at_custom_roles
    BEFORE UPDATE ON custom_roles FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_user_business_roles ON user_business_roles;
CREATE TRIGGER set_updated_at_user_business_roles
    BEFORE UPDATE ON user_business_roles FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_categories ON categories;
CREATE TRIGGER set_updated_at_categories
    BEFORE UPDATE ON categories FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_suppliers ON suppliers;
CREATE TRIGGER set_updated_at_suppliers
    BEFORE UPDATE ON suppliers FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_products ON products;
CREATE TRIGGER set_updated_at_products
    BEFORE UPDATE ON products FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_inventory ON inventory;
CREATE TRIGGER set_updated_at_inventory
    BEFORE UPDATE ON inventory FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_carts ON carts;
CREATE TRIGGER set_updated_at_carts
    BEFORE UPDATE ON carts FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_cart_items ON cart_items;
CREATE TRIGGER set_updated_at_cart_items
    BEFORE UPDATE ON cart_items FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_invoices ON invoices;
CREATE TRIGGER set_updated_at_invoices
    BEFORE UPDATE ON invoices FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_sales ON sales;
CREATE TRIGGER set_updated_at_sales
    BEFORE UPDATE ON sales FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_sale_items ON sale_items;
CREATE TRIGGER set_updated_at_sale_items
    BEFORE UPDATE ON sale_items FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_updated_at_payment_intents ON payment_intents;
CREATE TRIGGER set_updated_at_payment_intents
    BEFORE UPDATE ON payment_intents FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();




-- FILE: 002_branch_model.sql

-- 002_branch_model.sql
-- LedgerMind OS MVP — Branch model migration.
-- Adds a `branches` table scoped to a business and links branch_id to
-- inventory, carts, sales, invoices, and inventory_logs.
--
-- Notes:
--   * Idempotent: DROP CONSTRAINT IF EXISTS / ADD CONSTRAINT and
--     CREATE INDEX IF NOT EXISTS patterns are used throughout.
--   * Inventory is keyed per branch (product_id, branch_id) after this migration.
--   * RLS policies and business-branch consistency helpers live in later
--     Security / Payment agent migrations.


-- ============================================================
-- 1. Branches table
-- ============================================================

CREATE TABLE IF NOT EXISTS branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    location VARCHAR(255),
    phone VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(business_id, name)
);

CREATE INDEX IF NOT EXISTS idx_branches_business ON branches(business_id);
CREATE INDEX IF NOT EXISTS idx_branches_active ON branches(business_id) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS set_updated_at_branches ON branches;
CREATE TRIGGER set_updated_at_branches
    BEFORE UPDATE ON branches FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- ============================================================
-- 2. Inventory: per-branch stock records
-- ============================================================

ALTER TABLE inventory
    ADD COLUMN IF NOT EXISTS branch_id UUID;

ALTER TABLE inventory
    DROP CONSTRAINT IF EXISTS pk_inventory;

ALTER TABLE inventory
    ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE inventory
    DROP CONSTRAINT IF EXISTS fk_inventory_branch;

ALTER TABLE inventory
    ADD CONSTRAINT fk_inventory_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

ALTER TABLE inventory
    ADD CONSTRAINT pk_inventory PRIMARY KEY (product_id, branch_id);

CREATE INDEX IF NOT EXISTS idx_inventory_branch ON inventory(branch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_business_branch ON inventory(business_id, branch_id);


-- ============================================================
-- 3. Carts: every POS session belongs to a branch
-- ============================================================

ALTER TABLE carts
    ADD COLUMN IF NOT EXISTS branch_id UUID;

ALTER TABLE carts
    ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE carts
    DROP CONSTRAINT IF EXISTS fk_carts_branch;

ALTER TABLE carts
    ADD CONSTRAINT fk_carts_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_carts_branch ON carts(branch_id);
CREATE INDEX IF NOT EXISTS idx_carts_business_branch ON carts(business_id, branch_id);


-- ============================================================
-- 4. Sales: finalized transactions are branch-scoped
-- ============================================================

ALTER TABLE sales
    ADD COLUMN IF NOT EXISTS branch_id UUID;

ALTER TABLE sales
    ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE sales
    DROP CONSTRAINT IF EXISTS fk_sales_branch;

ALTER TABLE sales
    ADD CONSTRAINT fk_sales_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_sales_branch ON sales(branch_id);
CREATE INDEX IF NOT EXISTS idx_sales_business_branch ON sales(business_id, branch_id);


-- ============================================================
-- 5. Invoices: receipt records are branch-scoped
-- ============================================================

ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS branch_id UUID;

ALTER TABLE invoices
    ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE invoices
    DROP CONSTRAINT IF EXISTS fk_invoices_branch;

ALTER TABLE invoices
    ADD CONSTRAINT fk_invoices_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_invoices_branch ON invoices(branch_id);
CREATE INDEX IF NOT EXISTS idx_invoices_business_branch ON invoices(business_id, branch_id);


-- ============================================================
-- 6. Inventory Logs: record which branch stock moved
-- ============================================================

ALTER TABLE inventory_logs
    ADD COLUMN IF NOT EXISTS branch_id UUID;

ALTER TABLE inventory_logs
    ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE inventory_logs
    DROP CONSTRAINT IF EXISTS fk_inventory_logs_branch;

ALTER TABLE inventory_logs
    ADD CONSTRAINT fk_inventory_logs_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_inventory_logs_branch ON inventory_logs(branch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_logs_business_branch ON inventory_logs(business_id, branch_id);




-- FILE: 003_auth_helpers.sql

-- 003_auth_helpers.sql
-- LedgerMind OS MVP — Authentication & RBAC helper functions.
--
-- All helpers are SECURITY DEFINER and return safe defaults (false / NULL)
-- for anonymous users. They are used by the RLS policies in
-- 004_rls_policies.sql so policies never call auth.uid() directly.

-- ============================================================
-- 1. Current authenticated user ID
-- ============================================================

CREATE OR REPLACE FUNCTION current_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. Current business from JWT claim
-- ============================================================

CREATE OR REPLACE FUNCTION current_business_id()
RETURNS UUID AS $$
BEGIN
    RETURN (auth.jwt() ->> 'business_id')::UUID;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 3. Business membership
-- ============================================================

CREATE OR REPLACE FUNCTION user_belongs_to_business(p_business_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF current_user_id() IS NULL OR p_business_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles
        WHERE user_id = current_user_id()
        AND business_id = p_business_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 4. Owner check
-- ============================================================

CREATE OR REPLACE FUNCTION user_is_owner(p_business_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF current_user_id() IS NULL OR p_business_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles ubr
        JOIN custom_roles cr ON ubr.role_id = cr.id
        WHERE ubr.user_id = current_user_id()
        AND ubr.business_id = p_business_id
        AND cr.name = 'owner'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 5. Permission check (looks at the user's role JSONB)
-- ============================================================

CREATE OR REPLACE FUNCTION user_has_permission(p_business_id UUID, p_permission TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    IF current_user_id() IS NULL OR p_business_id IS NULL OR p_permission IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM user_business_roles ubr
        JOIN custom_roles cr ON ubr.role_id = cr.id
        WHERE ubr.user_id = current_user_id()
        AND ubr.business_id = p_business_id
        AND cr.permissions ? p_permission
        AND (cr.permissions ->> p_permission)::boolean = true
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;




-- FILE: 004_rls_policies.sql

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




-- FILE: 005_paystack_webhook_rpc.sql

-- 005_paystack_webhook_rpc.sql
-- Paystack webhook RPCs: capture marker + atomic sale finalization.
-- These functions are intentionally self-contained and idempotent.
-- They depend on the core schema (payment_intents, inventory, carts, etc.)
-- created by migrations 001-004.

-- ============================================================
-- 1. process_payment_capture
-- Marks a payment intent as captured so safe_finalize_sale can run.
-- The unique constraint on payment_processing_markers makes this idempotent.
-- ============================================================
CREATE OR REPLACE FUNCTION process_payment_capture(
    p_payment_intent_id UUID,
    p_event_id UUID
) RETURNS BOOLEAN AS $func$
DECLARE
    v_pi RECORD;
BEGIN
    -- Lock the intent to serialize concurrent webhooks.
    SELECT * INTO v_pi
    FROM payment_intents WHERE id = p_payment_intent_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent % not found', p_payment_intent_id;
    END IF;

    -- The unique index on payment_processing_markers(payment_intent_id) ensures
    -- only the first caller wins; subsequent calls return false.
    BEGIN
        INSERT INTO payment_processing_markers (payment_intent_id, event_id)
        VALUES (p_payment_intent_id, p_event_id);
    EXCEPTION WHEN unique_violation THEN
        RETURN false;
    END;

    RETURN true;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. safe_finalize_sale
-- Atomic cross-table sale finalization with inventory decrement.
-- Attaches the capture marker itself, so a failure rolls back cleanly.
-- Returns the new sale UUID, or raises if the sale is already finalized.
-- ============================================================
CREATE OR REPLACE FUNCTION safe_finalize_sale(
    p_payment_intent_id UUID
) RETURNS UUID AS $func$
DECLARE
    v_pi RECORD;
    v_cart RECORD;
    v_item RECORD;
    v_branch_id UUID;
    v_subtotal DECIMAL := 0;
    v_old_qty INT;
    v_new_qty INT;
    v_payment_id UUID;
    v_invoice_id UUID;
    v_sale_id UUID;
    v_invoice_number VARCHAR;
    v_seq INT;
BEGIN
    -- Fetch and lock the intent.
    SELECT * INTO v_pi
    FROM payment_intents WHERE id = p_payment_intent_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment intent % not found', p_payment_intent_id;
    END IF;

    -- Idempotently attach the capture marker inside this transaction.
    BEGIN
        INSERT INTO payment_processing_markers (payment_intent_id, event_id)
        SELECT p_payment_intent_id, id
        FROM payment_events
        WHERE payment_intent_id = p_payment_intent_id
          AND event_type = 'payment_captured'
        LIMIT 1;
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM payment_processing_markers WHERE payment_intent_id = p_payment_intent_id
    ) THEN
        RAISE EXCEPTION 'No payment_captured event found for payment intent %', p_payment_intent_id;
    END IF;

    -- Lock the cart; fail loudly if it is missing or not active.
    SELECT * INTO v_cart FROM carts WHERE id = v_pi.cart_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cart % not found for payment intent %', v_pi.cart_id, p_payment_intent_id;
    END IF;

    IF v_cart.status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Cart % is not active. Already processed?', v_pi.cart_id;
    END IF;

    v_branch_id := v_cart.branch_id;

    -- Decrement branch inventory for each cart item and write immutable inventory logs.
    FOR v_item IN
        SELECT product_id, quantity, unit_price FROM cart_items
        WHERE cart_id = v_pi.cart_id ORDER BY product_id
    LOOP
        v_subtotal := v_subtotal + (v_item.quantity * v_item.unit_price);

        SELECT quantity INTO v_old_qty FROM inventory
        WHERE product_id = v_item.product_id AND branch_id = v_branch_id
        FOR UPDATE;

        IF NOT FOUND OR v_old_qty < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock or missing inventory for product %', v_item.product_id;
        END IF;

        UPDATE inventory
        SET quantity = quantity - v_item.quantity, updated_at = NOW()
        WHERE product_id = v_item.product_id AND branch_id = v_branch_id
        RETURNING quantity INTO v_new_qty;

        INSERT INTO inventory_logs (
            business_id, branch_id, product_id, old_quantity, new_quantity,
            change_amount, reason, actor_id
        ) VALUES (
            v_pi.business_id, v_branch_id, v_item.product_id, v_old_qty, v_new_qty,
            -v_item.quantity, 'SALE_EVENT', v_pi.created_by
        );
    END LOOP;

    -- Validate the cart amount matches the intent amount before mutating anything else.
    IF TRUNC(v_subtotal, 2) != TRUNC(v_pi.amount, 2) THEN
        RAISE EXCEPTION 'Cart amount (%) does not match payment intent amount (%)', v_subtotal, v_pi.amount;
    END IF;

    -- Create the legacy payment record. We deliberately NEVER store full PAN or CVV.
    -- Paystack Ghana uses the same charge channel for cards and mobile money;
    -- a channel column on payment_intents should be added in a later migration.
    INSERT INTO payments (
        business_id, cashier_id, method, amount, status, provider_reference
    ) VALUES (
        v_pi.business_id, v_pi.created_by, 'CARD', v_pi.amount, 'SUCCESS', v_pi.provider_reference
    ) RETURNING id INTO v_payment_id;

    -- Link the legacy payment and mark the intent completed.
    UPDATE payment_intents
    SET legacy_payment_id = v_payment_id, status = 'completed'
    WHERE id = p_payment_intent_id;

    -- Generate a collision-resistant invoice number scoped by branch.
    SELECT COALESCE(MAX(CAST(SPLIT_PART(invoice_number, '-', 4) AS INT)), 0) + 1
    INTO v_seq FROM invoices
    WHERE branch_id = v_branch_id
      AND invoice_number LIKE 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '%';

    v_invoice_number := 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(v_seq::TEXT, 6, '0');

    INSERT INTO invoices (
        business_id, branch_id, invoice_number, cashier_id, payment_id, subtotal, tax, total
    ) VALUES (
        v_pi.business_id, v_branch_id, v_invoice_number, v_pi.created_by, v_payment_id,
        v_subtotal, 0, v_subtotal
    ) RETURNING id INTO v_invoice_id;

    -- Create the sale.
    INSERT INTO sales (business_id, branch_id, invoice_id, payment_id, cashier_id)
    VALUES (v_pi.business_id, v_branch_id, v_invoice_id, v_payment_id, v_pi.created_by)
    RETURNING id INTO v_sale_id;

    -- Persist line items.
    INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
    SELECT v_sale_id, product_id, quantity, unit_price, (quantity * unit_price)
    FROM cart_items WHERE cart_id = v_pi.cart_id;

    -- Mark the cart completed.
    UPDATE carts
    SET status = 'COMPLETED', updated_at = NOW()
    WHERE id = v_pi.cart_id;

    RETURN v_sale_id;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;




-- FILE: 006_checkout_rpc.sql

-- 006_checkout_rpc.sql
-- LedgerMind OS Phase 2 — POS checkout and payment-intent RPCs.
--
-- Provides:
--   * process_checkout_cash() — idempotent cash sale, inventory decrement, audit trail.
--   * create_checkout_intent() — creates a cart + Paystack payment intent for card/MoMo.
--   * get_branch_catalog() / get_catalog_delta() — server-side full/delta sync helpers.
--
-- Notes:
--   * All functions are SECURITY DEFINER and validate the caller belongs to the business.
--   * Inventory is keyed per branch (product_id, branch_id) after 002_branch_model.sql.
--   * Legacy `payments` table is updated so existing receipt queries keep working.
--   * Payment events are appended for every checkout, including cash.

-- ============================================================
-- 1. Cash checkout
-- ============================================================

CREATE OR REPLACE FUNCTION process_checkout_cash(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_idempotency_key UUID,
    p_items JSONB,
    p_total_amount DECIMAL(12, 2)
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cart_id UUID;
    v_intent_id UUID;
    v_payment_id UUID;
    v_invoice_id UUID;
    v_sale_id UUID;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price DECIMAL(12, 2);
    v_computed_total DECIMAL(12, 2) := 0;
    v_existing_sale_id UUID;
    v_invoice_number VARCHAR(100);
BEGIN
    -- Caller must be the authenticated cashier and belong to the business.
    IF v_user_id IS NULL OR v_user_id != p_cashier_id THEN
        RAISE EXCEPTION 'Caller must be the cashier';
    END IF;

    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Cashier does not belong to business';
    END IF;

    -- Branch must be owned by the business and active.
    IF NOT EXISTS (
        SELECT 1
        FROM branches
        WHERE id = p_branch_id
          AND business_id = p_business_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Invalid branch';
    END IF;

    -- Idempotency: if a sale already exists for this key, return it.
    SELECT s.id
    INTO v_existing_sale_id
    FROM payment_intents pi
    LEFT JOIN sales s ON s.payment_id = pi.legacy_payment_id
    WHERE pi.idempotency_key = p_idempotency_key
      AND pi.business_id = p_business_id
    LIMIT 1;

    IF v_existing_sale_id IS NOT NULL THEN
        RETURN v_existing_sale_id;
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    -- Validate items, resolve current prices, and compute total.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid item: %', v_item;
        END IF;

        SELECT selling_price
        INTO v_unit_price
        FROM products
        WHERE id = v_product_id
          AND business_id = p_business_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found', v_product_id;
        END IF;

        v_computed_total := v_computed_total + (v_unit_price * v_quantity);

        -- Prevent oversell at checkout time.
        IF NOT EXISTS (
            SELECT 1
            FROM inventory
            WHERE product_id = v_product_id
              AND branch_id = p_branch_id
              AND quantity >= v_quantity
        ) THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_product_id;
        END IF;
    END LOOP;

    IF v_computed_total != p_total_amount THEN
        RAISE EXCEPTION 'Total amount mismatch: computed %, received %', v_computed_total, p_total_amount;
    END IF;

    -- Persist cart.
    INSERT INTO carts (business_id, branch_id, cashier_id, status)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'CHECKED_OUT')
    RETURNING id INTO v_cart_id;

    -- Persist cart items.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (
            SELECT selling_price
            FROM products
            WHERE id = v_product_id AND business_id = p_business_id
        );

        INSERT INTO cart_items (cart_id, product_id, quantity, unit_price)
        VALUES (v_cart_id, v_product_id, v_quantity, v_unit_price);
    END LOOP;

    -- Create a completed payment intent for the cash sale.
    INSERT INTO payment_intents (
        business_id, cart_id, amount, currency, idempotency_key,
        provider, status, created_by
    )
    VALUES (
        p_business_id, v_cart_id, p_total_amount, 'GHS', p_idempotency_key,
        'cash', 'completed', p_cashier_id
    )
    RETURNING id INTO v_intent_id;

    -- Append the capture event to the immutable ledger.
    INSERT INTO payment_events (payment_intent_id, event_type, provider, occurred_at)
    VALUES (v_intent_id, 'payment_captured', 'cash', NOW());

    -- Keep the legacy payment table in sync for receipts and dashboards.
    INSERT INTO payments (business_id, cashier_id, method, amount, status, provider_reference)
    VALUES (p_business_id, p_cashier_id, 'cash', p_total_amount, 'COMPLETED', p_idempotency_key::text)
    RETURNING id INTO v_payment_id;

    UPDATE payment_intents
    SET legacy_payment_id = v_payment_id
    WHERE id = v_intent_id;

    -- Invoice and sale records.
    v_invoice_number := 'INV-' || to_char(NOW(), 'YYYYMMDD') || '-' || substr(v_intent_id::text, 1, 8);

    INSERT INTO invoices (business_id, branch_id, invoice_number, cashier_id, payment_id, subtotal, tax, total)
    VALUES (p_business_id, p_branch_id, v_invoice_number, p_cashier_id, v_payment_id, v_computed_total, 0, v_computed_total)
    RETURNING id INTO v_invoice_id;

    INSERT INTO sales (business_id, branch_id, invoice_id, payment_id, cashier_id)
    VALUES (p_business_id, p_branch_id, v_invoice_id, v_payment_id, p_cashier_id)
    RETURNING id INTO v_sale_id;

    -- Decrement stock and write audit logs.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (
            SELECT selling_price
            FROM products
            WHERE id = v_product_id AND business_id = p_business_id
        );

        INSERT INTO sale_items (sale_id, product_id, quantity, unit_price, subtotal)
        VALUES (v_sale_id, v_product_id, v_quantity, v_unit_price, v_unit_price * v_quantity);

        UPDATE inventory
        SET quantity = quantity - v_quantity
        WHERE product_id = v_product_id AND branch_id = p_branch_id;

        INSERT INTO inventory_logs (business_id, branch_id, product_id, old_quantity, new_quantity, change_amount, reason, actor_id)
        SELECT business_id, branch_id, product_id, quantity + v_quantity, quantity, -v_quantity, 'sale', p_cashier_id
        FROM inventory
        WHERE product_id = v_product_id AND branch_id = p_branch_id;
    END LOOP;

    INSERT INTO activity_logs (business_id, actor_id, action, entity_table, entity_id, metadata)
    VALUES (
        p_business_id, p_cashier_id, 'sale_completed', 'sales', v_sale_id,
        jsonb_build_object('payment_intent_id', v_intent_id, 'total', v_computed_total, 'method', 'cash')
    );

    RETURN v_sale_id;
END;
$$;


-- ============================================================
-- 2. Payment intent creation for Paystack card / MoMo
-- ============================================================

CREATE OR REPLACE FUNCTION create_checkout_intent(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_idempotency_key UUID,
    p_items JSONB,
    p_total_amount DECIMAL(12, 2),
    p_method TEXT DEFAULT 'card'
) RETURNS TABLE(intent_id UUID, cart_id UUID, reference TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_cart_id UUID;
    v_intent_id UUID;
    v_reference TEXT;
    v_item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price DECIMAL(12, 2);
    v_computed_total DECIMAL(12, 2) := 0;
BEGIN
    IF v_user_id IS NULL OR v_user_id != p_cashier_id THEN
        RAISE EXCEPTION 'Caller must be the cashier';
    END IF;

    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Cashier does not belong to business';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM branches
        WHERE id = p_branch_id
          AND business_id = p_business_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Invalid branch';
    END IF;

    -- Idempotency: return existing intent if the caller retries.
    SELECT pi.id, pi.cart_id, pi.provider_reference
    INTO v_intent_id, v_cart_id, v_reference
    FROM payment_intents pi
    WHERE pi.idempotency_key = p_idempotency_key
      AND pi.business_id = p_business_id;

    IF v_intent_id IS NOT NULL THEN
        RETURN QUERY SELECT v_intent_id, v_cart_id, v_reference;
        RETURN;
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid item: %', v_item;
        END IF;

        SELECT selling_price
        INTO v_unit_price
        FROM products
        WHERE id = v_product_id
          AND business_id = p_business_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found', v_product_id;
        END IF;

        v_computed_total := v_computed_total + (v_unit_price * v_quantity);

        IF NOT EXISTS (
            SELECT 1
            FROM inventory
            WHERE product_id = v_product_id
              AND branch_id = p_branch_id
              AND quantity >= v_quantity
        ) THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_product_id;
        END IF;
    END LOOP;

    IF v_computed_total != p_total_amount THEN
        RAISE EXCEPTION 'Total amount mismatch: computed %, received %', v_computed_total, p_total_amount;
    END IF;

    INSERT INTO carts (business_id, branch_id, cashier_id, status)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'ACTIVE')
    RETURNING id INTO v_cart_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;
        v_unit_price := (
            SELECT selling_price
            FROM products
            WHERE id = v_product_id AND business_id = p_business_id
        );

        INSERT INTO cart_items (cart_id, product_id, quantity, unit_price)
        VALUES (v_cart_id, v_product_id, v_quantity, v_unit_price);
    END LOOP;

    v_reference := p_idempotency_key::text;

    INSERT INTO payment_intents (
        business_id, cart_id, amount, currency, idempotency_key,
        provider, provider_reference, status, created_by
    )
    VALUES (
        p_business_id, v_cart_id, p_total_amount, 'GHS', p_idempotency_key,
        'paystack', v_reference, 'initiated', p_cashier_id
    )
    RETURNING id INTO v_intent_id;

    RETURN QUERY SELECT v_intent_id, v_cart_id, v_reference;
END;
$$;


-- ============================================================
-- 3. Server-side catalog helpers for Flutter sync
-- ============================================================

CREATE OR REPLACE FUNCTION get_branch_catalog(
    p_business_id UUID,
    p_branch_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN jsonb_build_object(
        'categories', COALESCE(
            (SELECT jsonb_agg(to_jsonb(c))
             FROM categories c
             WHERE c.business_id = p_business_id AND c.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'products', COALESCE(
            (SELECT jsonb_agg(to_jsonb(p))
             FROM products p
             WHERE p.business_id = p_business_id AND p.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'inventory', COALESCE(
            (SELECT jsonb_agg(to_jsonb(i))
             FROM inventory i
             WHERE i.business_id = p_business_id AND i.branch_id = p_branch_id),
            '[]'::jsonb
        )
    );
END;
$$;


CREATE OR REPLACE FUNCTION get_catalog_delta(
    p_business_id UUID,
    p_branch_id UUID,
    p_since TIMESTAMPTZ
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN jsonb_build_object(
        'categories', COALESCE(
            (SELECT jsonb_agg(to_jsonb(c))
             FROM categories c
             WHERE c.business_id = p_business_id
               AND c.updated_at > p_since
               AND c.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'products', COALESCE(
            (SELECT jsonb_agg(to_jsonb(p))
             FROM products p
             WHERE p.business_id = p_business_id
               AND p.updated_at > p_since
               AND p.deleted_at IS NULL),
            '[]'::jsonb
        ),
        'inventory', COALESCE(
            (SELECT jsonb_agg(to_jsonb(i))
             FROM inventory i
             WHERE i.business_id = p_business_id
               AND i.branch_id = p_branch_id
               AND i.updated_at > p_since),
            '[]'::jsonb
        ),
        'since', p_since
    );
END;
$$;




-- FILE: 007_refunds.sql

-- 007_refunds.sql
-- Refunds and returns support for LedgerMind OS MVP.

CREATE TABLE IF NOT EXISTS refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    cashier_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'voided')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refund_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id UUID NOT NULL REFERENCES refunds(id) ON DELETE CASCADE,
    sale_item_id UUID NOT NULL REFERENCES sale_items(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Refund indexes
CREATE INDEX IF NOT EXISTS idx_refunds_business ON refunds(business_id);
CREATE INDEX IF NOT EXISTS idx_refunds_branch ON refunds(branch_id);
CREATE INDEX IF NOT EXISTS idx_refunds_sale ON refunds(sale_id);
CREATE INDEX IF NOT EXISTS idx_refund_items_refund ON refund_items(refund_id);

-- Helper: quantity already refunded for a sale item
CREATE OR REPLACE FUNCTION refunded_quantity(p_sale_item_id UUID)
RETURNS INTEGER AS $$
DECLARE
    total INTEGER;
BEGIN
    SELECT COALESCE(SUM(ri.quantity), 0)
    INTO total
    FROM refund_items ri
    JOIN refunds r ON r.id = ri.refund_id
    WHERE ri.sale_item_id = p_sale_item_id
      AND r.status = 'completed';

    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- Process a refund. Returns the refund id.
CREATE OR REPLACE FUNCTION process_refund(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_sale_id UUID,
    p_items JSONB,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_refund_id UUID;
    v_total NUMERIC(12,2) := 0;
    item JSONB;
    v_sale_item RECORD;
    v_sale_item_id UUID;
    v_product_id UUID;
    v_quantity INTEGER;
    v_unit_price NUMERIC(12,2);
    v_subtotal NUMERIC(12,2);
    v_already_refunded INTEGER;
BEGIN
    -- Authorization and ownership checks
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'User does not belong to business';
    END IF;

    IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
        RAISE EXCEPTION 'Unauthorized cashier';
    END IF;

    -- Verify sale exists and belongs to business/branch
    PERFORM 1 FROM sales
    WHERE id = p_sale_id
      AND business_id = p_business_id
      AND branch_id = p_branch_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale not found in branch';
    END IF;

    -- Create refund record
    INSERT INTO refunds (business_id, branch_id, sale_id, cashier_id, reason, total_amount)
    VALUES (p_business_id, p_branch_id, p_sale_id, p_cashier_id, p_reason, 0)
    RETURNING id INTO v_refund_id;

    -- Process each item
    FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_sale_item_id := (item->>'sale_item_id')::UUID;
        v_quantity := (item->>'quantity')::INTEGER;

        SELECT si.id, si.product_id, si.quantity, si.unit_price
        INTO v_sale_item
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        WHERE si.id = v_sale_item_id
          AND s.id = p_sale_id
          AND s.business_id = p_business_id;

        IF v_sale_item.id IS NULL THEN
            RAISE EXCEPTION 'Invalid sale item: %', v_sale_item_id;
        END IF;

        v_already_refunded := refunded_quantity(v_sale_item_id);
        IF v_already_refunded + v_quantity > v_sale_item.quantity THEN
            RAISE EXCEPTION 'Refund quantity exceeds sold quantity for item %', v_sale_item_id;
        END IF;

        v_product_id := v_sale_item.product_id;
        v_unit_price := v_sale_item.unit_price;
        v_subtotal := v_unit_price * v_quantity;
        v_total := v_total + v_subtotal;

        INSERT INTO refund_items (refund_id, sale_item_id, product_id, quantity, unit_price, subtotal)
        VALUES (v_refund_id, v_sale_item_id, v_product_id, v_quantity, v_unit_price, v_subtotal);

        -- Return inventory to stock
        UPDATE inventory
        SET quantity = quantity + v_quantity,
            updated_at = now()
        WHERE product_id = v_product_id
          AND branch_id = p_branch_id;

        -- Insert inventory log
        INSERT INTO inventory_logs (business_id, branch_id, product_id, quantity_change, reason, created_by)
        VALUES (p_business_id, p_branch_id, v_product_id, v_quantity, 'refund', p_cashier_id);
    END LOOP;

    -- Update refund total
    UPDATE refunds
    SET total_amount = v_total,
        updated_at = now()
    WHERE id = v_refund_id;

    -- Audit log
    INSERT INTO activity_logs (business_id, branch_id, user_id, action, details)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'refund_created',
            jsonb_build_object('refund_id', v_refund_id, 'sale_id', p_sale_id, 'amount', v_total));

    RETURN v_refund_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS on refund tables
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE refund_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS refunds_business_access ON refunds;
CREATE POLICY refunds_business_access ON refunds
    FOR ALL
    TO authenticated
    USING (user_belongs_to_business(business_id));

DROP POLICY IF EXISTS refund_items_business_access ON refund_items;
CREATE POLICY refund_items_business_access ON refund_items
    FOR ALL
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM refunds r
        WHERE r.id = refund_items.refund_id
          AND user_belongs_to_business(r.business_id)
    ));




-- FILE: 008_push_subscriptions.sql

-- 008_push_subscriptions.sql
-- Stores web push subscriptions for critical alerts.

CREATE TABLE IF NOT EXISTS push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL,
    p256dh TEXT NOT NULL,
    auth TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user ON push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_business ON push_subscriptions(business_id);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS push_subscriptions_user_access ON push_subscriptions;
CREATE POLICY push_subscriptions_user_access ON push_subscriptions
    FOR ALL
    TO authenticated
    USING (user_id = auth.uid());




-- FILE: 009_shifts.sql

-- 009_shifts.sql
-- Cashier shift audit and reconciliation.

CREATE TABLE IF NOT EXISTS shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    cashier_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ,
    opening_float NUMERIC(12,2) NOT NULL DEFAULT 0,
    expected_cash NUMERIC(12,2),
    actual_cash NUMERIC(12,2),
    discrepancy NUMERIC(12,2),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'verified')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shifts_business ON shifts(business_id);
CREATE INDEX IF NOT EXISTS idx_shifts_branch ON shifts(branch_id);
CREATE INDEX IF NOT EXISTS idx_shifts_cashier ON shifts(cashier_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts(status);

ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shifts_business_access ON shifts;
CREATE POLICY shifts_business_access ON shifts
    FOR ALL
    TO authenticated
    USING (user_belongs_to_business(business_id));

-- Close a shift and compute expected cash from sales during the shift.
CREATE OR REPLACE FUNCTION close_shift(
    p_shift_id UUID,
    p_actual_cash NUMERIC(12,2),
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_shift RECORD;
    v_expected NUMERIC(12,2);
BEGIN
    SELECT * INTO v_shift FROM shifts WHERE id = p_shift_id;
    IF v_shift IS NULL THEN
        RAISE EXCEPTION 'Shift not found';
    END IF;

    IF v_shift.status <> 'open' THEN
        RAISE EXCEPTION 'Shift is not open';
    END IF;

    SELECT COALESCE(SUM(p.amount), 0)
    INTO v_expected
    FROM sales s
    JOIN payments p ON p.id = s.payment_id
    WHERE s.cashier_id = v_shift.cashier_id
      AND s.branch_id = v_shift.branch_id
      AND s.created_at >= v_shift.opened_at
      AND s.created_at <= now()
      AND p.method = 'cash';

    v_expected := v_expected + v_shift.opening_float;

    UPDATE shifts
    SET closed_at = now(),
        actual_cash = p_actual_cash,
        expected_cash = v_expected,
        discrepancy = p_actual_cash - v_expected,
        status = 'closed',
        notes = p_notes,
        updated_at = now()
    WHERE id = p_shift_id;

    INSERT INTO activity_logs (business_id, branch_id, user_id, action, details)
    VALUES (v_shift.business_id, v_shift.branch_id, v_shift.cashier_id, 'shift_closed',
            jsonb_build_object('shift_id', p_shift_id,
                               'expected_cash', v_expected,
                               'actual_cash', p_actual_cash,
                               'discrepancy', p_actual_cash - v_expected));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Open a shift only if the cashier has no other open shift for this branch.
CREATE OR REPLACE FUNCTION open_shift(
    p_business_id UUID,
    p_branch_id UUID,
    p_cashier_id UUID,
    p_opening_float NUMERIC(12,2) DEFAULT 0
)
RETURNS UUID AS $$
DECLARE
    v_existing UUID;
    v_shift_id UUID;
BEGIN
    IF NOT user_belongs_to_business(p_business_id) THEN
        RAISE EXCEPTION 'User does not belong to business';
    END IF;

    IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT id INTO v_existing
    FROM shifts
    WHERE cashier_id = p_cashier_id
      AND branch_id = p_branch_id
      AND status = 'open'
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        RAISE EXCEPTION 'Cashier already has an open shift';
    END IF;

    INSERT INTO shifts (business_id, branch_id, cashier_id, opening_float)
    VALUES (p_business_id, p_branch_id, p_cashier_id, p_opening_float)
    RETURNING id INTO v_shift_id;

    INSERT INTO activity_logs (business_id, branch_id, user_id, action, details)
    VALUES (p_business_id, p_branch_id, p_cashier_id, 'shift_opened',
            jsonb_build_object('shift_id', v_shift_id, 'opening_float', p_opening_float));

    RETURN v_shift_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;





-- SEED

-- 001_default_roles.sql
-- LedgerMind OS MVP — Default business roles seed.
--
-- * Defines owner, manager, cashier, and accountant roles for every
--   business using a JSONB permission map.
-- * Uses a trigger so new businesses automatically receive the four
--   default roles on insert.
-- * Backfills default roles for any businesses that already exist.

-- ============================================================
-- 1. Trigger function: create default roles for a business
-- ============================================================

CREATE OR REPLACE FUNCTION create_default_roles_for_business()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO custom_roles (business_id, name, permissions) VALUES
        (NEW.id, 'owner', '{"manage_products": true, "manage_inventory": true, "manage_users": true, "process_sales": true, "view_reports": true, "view_inventory": true, "view_sales": true}'::jsonb),
        (NEW.id, 'manager', '{"manage_products": true, "manage_inventory": true, "manage_users": true, "process_sales": true, "view_reports": true}'::jsonb),
        (NEW.id, 'cashier', '{"process_sales": true, "view_inventory": true}'::jsonb),
        (NEW.id, 'accountant', '{"view_reports": true, "view_sales": true, "view_inventory": true}'::jsonb)
    ON CONFLICT (business_id, name) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. Attach trigger to businesses
-- ============================================================

DROP TRIGGER IF EXISTS trg_create_default_roles ON businesses;
CREATE TRIGGER trg_create_default_roles
    AFTER INSERT ON businesses
    FOR EACH ROW
    EXECUTE FUNCTION create_default_roles_for_business();


-- ============================================================
-- 3. Seed function for reuse and verification
-- ============================================================

CREATE OR REPLACE FUNCTION seed_default_roles()
RETURNS VOID AS $$
DECLARE
    b businesses%ROWTYPE;
BEGIN
    FOR b IN SELECT * FROM businesses LOOP
        INSERT INTO custom_roles (business_id, name, permissions) VALUES
            (b.id, 'owner', '{"manage_products": true, "manage_inventory": true, "manage_users": true, "process_sales": true, "view_reports": true, "view_inventory": true, "view_sales": true}'::jsonb),
            (b.id, 'manager', '{"manage_products": true, "manage_inventory": true, "manage_users": true, "process_sales": true, "view_reports": true}'::jsonb),
            (b.id, 'cashier', '{"process_sales": true, "view_inventory": true}'::jsonb),
            (b.id, 'accountant', '{"view_reports": true, "view_sales": true, "view_inventory": true}'::jsonb)
        ON CONFLICT (business_id, name) DO NOTHING;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Backfill existing businesses on seed
SELECT seed_default_roles();

