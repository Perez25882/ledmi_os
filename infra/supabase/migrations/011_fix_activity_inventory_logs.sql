-- 011_fix_activity_inventory_logs.sql
-- Adds branch_id columns to activity_logs and inventory_logs if they were created
-- by earlier migrations before these columns were added. Fixes are idempotent.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'activity_logs' AND column_name = 'branch_id'
    ) THEN
        ALTER TABLE activity_logs ADD COLUMN branch_id UUID REFERENCES branches(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'inventory_logs' AND column_name = 'branch_id'
    ) THEN
        ALTER TABLE inventory_logs ADD COLUMN branch_id UUID REFERENCES branches(id) ON DELETE SET NULL;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_activity_logs_branch ON activity_logs(branch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_logs_branch ON inventory_logs(branch_id);
