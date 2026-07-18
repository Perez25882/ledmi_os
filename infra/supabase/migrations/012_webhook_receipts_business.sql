-- 012_webhook_receipts_business.sql
-- LedgerMind OS MVP — Add business_id to webhook_receipts and fix the
-- cross-business data leak in the RLS SELECT policy (gap #3 from
-- docs/DEPT_ENGINEERING_STATUS.md §3).
--
-- The old policy in 004_rls_policies.sql granted SELECT to any user with
-- view_reports in their *current* JWT business, regardless of which business
-- the receipt actually belonged to — so a user could read webhook receipts
-- for ALL businesses. This migration adds business_id, backfills it from the
-- matched payment_intent, and re-scopes the policy to business_id.
--
-- Idempotent. Safe to re-run.

-- ============================================================
-- 1. Add business_id column
-- ============================================================
ALTER TABLE webhook_receipts ADD COLUMN IF NOT EXISTS business_id UUID;

-- ============================================================
-- 2. Backfill business_id from the matched payment_intent.
--    webhook_receipts has no FK to payment_intents, so we join on the
--    Paystack provider reference stored in raw_payload -> data.reference.
--    Only rows where business_id IS NULL are touched, so re-runs are safe.
--    Receipts with no matching intent (transfers, unmatched webhooks) keep
--    business_id NULL — they are not readable by any business user under the
--    new policy (service role / Edge Function still has access).
-- ============================================================
UPDATE webhook_receipts wr
SET business_id = pi.business_id
FROM payment_intents pi
WHERE wr.business_id IS NULL
  AND pi.provider_reference = (wr.raw_payload -> 'data' ->> 'reference');

-- ============================================================
-- 3. Index for business-scoped queries
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_webhook_receipts_business
ON webhook_receipts(business_id);

-- ============================================================
-- 4. Foreign key to businesses(id) (idempotent via DO block).
--    ON DELETE SET NULL keeps receipts auditable even if a business is
--    removed; business_id is intentionally nullable for unmatched webhooks.
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_webhook_receipts_business'
  ) THEN
    ALTER TABLE webhook_receipts
      ADD CONSTRAINT fk_webhook_receipts_business
      FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================
-- 5. Set NOT NULL only when every row has a resolvable business_id.
--    Because some webhooks legitimately have no matching payment_intent
--    (e.g. transfer events, orphaned retries), the column is left nullable
--    whenever unresolvable NULLs remain. If a future cleanup resolves all
--    NULLs, re-running this block will promote the column to NOT NULL.
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM webhook_receipts WHERE business_id IS NULL) THEN
    ALTER TABLE webhook_receipts ALTER COLUMN business_id SET NOT NULL;
  END IF;
END $$;

-- ============================================================
-- 6. Replace the leaky SELECT policy.
--    New policy scopes reads to receipts whose business_id matches the
--    user's current JWT business and requires view_reports (or ownership)
--    on that business. Receipts with NULL business_id are unreadable by any
--    business-scoped user (only service role can see them).
-- ============================================================
DROP POLICY IF EXISTS "webhook_receipts_select_finance" ON webhook_receipts;
CREATE POLICY "webhook_receipts_select_finance" ON webhook_receipts
FOR SELECT USING (
    business_id = current_business_id()
    AND (
        user_is_owner(business_id)
        OR user_has_permission(business_id, 'view_reports')
    )
);
