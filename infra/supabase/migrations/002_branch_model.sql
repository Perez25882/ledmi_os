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
