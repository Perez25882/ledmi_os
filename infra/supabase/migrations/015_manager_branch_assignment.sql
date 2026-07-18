-- 015_manager_branch_assignment.sql
-- LedgerMind OS MVP — Explicit branch assignment for managers.
--
-- Resolves the blocker flagged by both the Flutter POS and Dashboard RBAC
-- tasks: user_business_roles had no branch_id, so managers were scoped to
-- context.branchId (the first branch) with no way to assign a specific branch
-- or multiple branches. This migration adds a nullable branch_id column and a
-- helper that returns the set of branch IDs a user may access.
--
-- Semantics:
--   * NULL branch_id  → user has access to ALL branches of the business
--                       (owners, accountants). This is the default for
--                       existing rows, preserving backward compatibility.
--   * non-NULL        → user is scoped to that single branch (managers,
--                       cashiers). A future multi-branch-manager model can
--                       promote this to a separate join table; for the MVP
--                       single-branch assignment is sufficient.
--
-- Idempotent. Safe to re-run.

-- ============================================================
-- 1. Add branch_id column (nullable)
-- ============================================================
ALTER TABLE user_business_roles ADD COLUMN IF NOT EXISTS branch_id UUID;

-- ============================================================
-- 2. Foreign key to branches(id) (idempotent via DO block)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_user_business_roles_branch'
  ) THEN
    ALTER TABLE user_business_roles
      ADD CONSTRAINT fk_user_business_roles_branch
      FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- 3. Index for branch-scoped membership lookups
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_user_business_roles_branch
    ON user_business_roles(business_id, branch_id)
    WHERE branch_id IS NOT NULL;

-- ============================================================
-- 4. RLS policy for branch_id column reads
--    The existing user_business_roles_select policy already grants SELECT
--    to business members and owners. No new policy needed — the column is
--    covered by the existing row-level policy. We only ensure the column
--    cannot be used to escalate: a user cannot set their own branch_id to
--    gain access to another branch, because the manage_owners policy
--    already restricts writes to owners only.
-- ============================================================

-- ============================================================
-- 5. Helper: user_accessible_branches(p_business_id)
--    Returns the set of branch IDs the current user may access within a
--    business. Returns NULL (meaning "all branches") when the user has a
--    role with NULL branch_id (owner/accountant). Returns a specific set
--    when the user is branch-scoped (manager/cashier).
--
--    Callers: dashboard getScopedBranchFilter(), Flutter session_manager.
--    Convention: NULL return = no branch filter (all branches).
-- ============================================================
CREATE OR REPLACE FUNCTION user_accessible_branches(p_business_id UUID)
RETURNS SETOF UUID AS $$
DECLARE
    v_user UUID := current_user_id();
    v_has_unscoped BOOLEAN;
BEGIN
    IF v_user IS NULL OR p_business_id IS NULL THEN
        RETURN;
    END IF;

    -- If the user has ANY role row with NULL branch_id for this business,
    -- they have cross-branch access (owner / accountant). Return NULL set
    -- is not directly expressible in SETOF, so we return all branch IDs
    -- of the business instead — callers treat "all branches" as no filter.
    SELECT EXISTS (
        SELECT 1 FROM user_business_roles
        WHERE user_id = v_user
          AND business_id = p_business_id
          AND branch_id IS NULL
    ) INTO v_has_unscoped;

    IF v_has_unscoped THEN
        RETURN QUERY SELECT id FROM branches
                     WHERE business_id = p_business_id AND deleted_at IS NULL;
        RETURN;
    END IF;

    -- Otherwise return only the explicitly assigned branches.
    RETURN QUERY
        SELECT ubr.branch_id
        FROM user_business_roles ubr
        WHERE ubr.user_id = v_user
          AND ubr.business_id = p_business_id
          AND ubr.branch_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
