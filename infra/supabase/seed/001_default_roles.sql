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
