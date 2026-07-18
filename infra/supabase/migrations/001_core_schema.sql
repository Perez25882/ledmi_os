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
    branch_id UUID,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    old_quantity INT NOT NULL,
    new_quantity INT NOT NULL,
    change_amount INT NOT NULL,
    reason VARCHAR(255) NOT NULL,
    actor_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_logs_business ON inventory_logs(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_logs_branch ON inventory_logs(branch_id);
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
    branch_id UUID,
    actor_id UUID REFERENCES auth.users(id),
    action VARCHAR(255) NOT NULL,
    entity_table VARCHAR(100),
    entity_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_logs_business ON activity_logs(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_branch ON activity_logs(branch_id);
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
