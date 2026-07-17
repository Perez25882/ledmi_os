-- 010_inventory_reorder_level.sql
-- LedgerMind OS MVP — Add reorder_level to per-branch inventory.

ALTER TABLE inventory
    ADD COLUMN IF NOT EXISTS reorder_level INT NOT NULL DEFAULT 10;

CREATE INDEX IF NOT EXISTS idx_inventory_reorder_level ON inventory(reorder_level);
