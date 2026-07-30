-- ============================================================
-- 016_branch_shop_fields.sql
--
-- Extends `branches` with the shop-detail fields the Flutter POS
-- Shop Details screen needs (MoMo number, receipt footer, tax id,
-- contact email, opening hours). The POS previously stored these
-- only in a local Hive box; this migration gives them a real home
-- in the shared backend so the dashboard and POS stay in sync.
--
-- All columns are nullable for backward compatibility with existing
-- branches. RLS reuses the existing branch policies (members read,
-- owners/managers write).
-- ============================================================

ALTER TABLE branches
    ADD COLUMN IF NOT EXISTS email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS momo_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS tax_id VARCHAR(50),
    ADD COLUMN IF NOT EXISTS opening_hours VARCHAR(100),
    ADD COLUMN IF NOT EXISTS footer_text VARCHAR(150);

-- Currency is a business-level concern; add it to `businesses`.
ALTER TABLE businesses
    ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'GHS';

COMMENT ON COLUMN branches.email IS 'Contact email for this branch (POS shop details).';
COMMENT ON COLUMN branches.momo_number IS 'Mobile Money merchant number for this branch.';
COMMENT ON COLUMN branches.tax_id IS 'GRA TIN / tax registration id for this branch.';
COMMENT ON COLUMN branches.opening_hours IS 'Human-readable opening hours, e.g. "8:00 AM - 9:00 PM".';
COMMENT ON COLUMN branches.footer_text IS 'Receipt footer text printed on receipts for this branch.';
COMMENT ON COLUMN businesses.currency IS 'ISO 4217 currency code, default GHS for Ghana.';
