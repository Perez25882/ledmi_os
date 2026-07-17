# LedgerMind OS — Engineering Department Status Report

**Author:** Kwame Asante, VP Engineering
**Date:** 2026-07-13
**Audience:** CEO (Devin), Engineering ICs
**Scope:** Phase 1 backend, payments, security/RLS, and sync deliverables.

---

## 1. Area Summary

| # | Area | Files | Completion % | Notes |
|---|------|-------|-------------|-------|
| 1 | Core schema migration | `infra/supabase/migrations/001_core_schema.sql` | 85% | Idempotent DDL, but **forward-references `branches(id)`** (lines 156, 298) before `branches` exists in 002. Breaks clean `db reset`. |
| 2 | Branch model migration | `infra/supabase/migrations/002_branch_model.sql` | 95% | Idempotent ALTER pattern; `SET NOT NULL` on `branch_id` will fail if pre-existing rows are null. |
| 3 | Auth helpers | `infra/supabase/migrations/003_auth_helpers.sql` | 100% | 5 SECURITY DEFINER helpers, safe defaults, `CREATE OR REPLACE`. Solid. |
| 4 | RLS policies | `infra/supabase/migrations/004_rls_policies.sql` | 90% | Covers all 20 tables from 001/002; `webhook_receipts` policy is weak (no `business_id`, relies on JWT `current_business_id()`). |
| 5 | Paystack webhook RPC | `infra/supabase/migrations/005_paystack_webhook_rpc.sql` | 90% | `process_payment_capture` + `safe_finalize_sale` are idempotent and transactional; `safe_finalize_sale` hardcodes `method='CARD'` (no MoMo). |
| 6 | Checkout RPCs | `infra/supabase/migrations/006_checkout_rpc.sql` | 85% | Cash + intent + catalog sync RPCs; **doc/code mismatch on `p_total_amount` units** (SYNC_PROTOCOL says pesewas, code compares as GHS decimals). |
| 7 | Refunds | `infra/supabase/migrations/007_refunds.sql` | 70% | Tables + `process_refund` work, but **`process_refund` is not idempotent** (no idempotency key). RLS policies missing `WITH CHECK`. |
| 8 | Push subscriptions | `infra/supabase/migrations/008_push_subscriptions.sql` | 95% | Clean, idempotent, user-scoped RLS. |
| 9 | Shifts | `infra/supabase/migrations/009_shifts.sql` | 75% | `close_shift` is SECURITY DEFINER but **does not verify caller identity or business membership** — any authenticated user can close any shift. |
| 10 | Inventory reorder level | `infra/supabase/migrations/010_inventory_reorder_level.sql` | 100% | Idempotent `ADD COLUMN IF NOT EXISTS`. |
| 11 | Activity/inventory log fix | `infra/supabase/migrations/011_fix_activity_inventory_logs.sql` | 100% | Redundant given 001 already adds `branch_id`, but harmless and idempotent. |
| 12 | Paystack webhook Edge Function | `infra/supabase/functions/paystack-webhook/index.ts` | 95% | HMAC-SHA512 verified with `timingSafeEqual`; idempotent via receipts + event marker + `safe_finalize_sale`; no PAN/CVV logging. |
| 13 | Paystack initiate Edge Function | `infra/supabase/functions/paystack-initiate/index.ts` | 90% | Verifies caller JWT, ownership, and intent status; 409 on re-init. Uses synthetic `cashier-<id>@ledgermind.app` email. |
| 14 | Sync protocol doc | `docs/SYNC_PROTOCOL.md` | 95% | Defines idempotency keys, offline queue, conflict matrix, RPC signatures, retry/backoff. Units mismatch with 006 code. |
| 15 | Security playbook | `docs/SECURITY.md` | 90% | Threat model, RLS, PCI, secrets, audit checklist. Checklist items still unchecked. |
| 16 | Architectural decisions | `docs/DECISIONS.md` | 100% | 12 locked ADs covering backend, offline, payments, AI, branch scoping. |
| 17 | Default roles seed | `infra/supabase/seed/001_default_roles.sql` | 100% | Trigger-based auto-seed of owner/manager/cashier/accountant; idempotent `ON CONFLICT`. |

**Department aggregate: ~90% of Phase 1 backend/security/payments/sync deliverables are present and largely correct. A handful of correctness and security gaps block a clean exit.**

---

## 2. What's Done

- **Schema foundation (001–002):** 20+ tables covering multi-tenant businesses, branches, RBAC, products, per-branch inventory, carts, sales, invoices, event-sourced payments (`payment_intents`, `payment_events`, `webhook_receipts`, `payment_processing_markers`), and audit logs. DDL is consistently idempotent (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `DROP TRIGGER IF EXISTS` / `CREATE TRIGGER`).
- **Auth & RBAC (003 + seed):** `current_user_id`, `current_business_id`, `user_belongs_to_business`, `user_is_owner`, `user_has_permission` — all `SECURITY DEFINER` with safe null/false defaults. Default roles auto-seeded via trigger with `ON CONFLICT DO NOTHING`.
- **RLS (004 + per-migration):** RLS enabled on every table from 001/002; deny-by-default posture with explicit member/owner/permission-scoped policies. Later migrations (007/008/009) enable RLS on their own tables.
- **Paystack webhook (005 + function):** HMAC-SHA512 verification with timing-safe compare, raw webhook receipt storage with unique constraint, canonical event mapping (`charge.success` → `payment_captured`, refund/chargeback handling), idempotent event append via partial unique index, and atomic sale finalization through `safe_finalize_sale` with `FOR UPDATE` locks and `payment_processing_markers` dedup. No PAN/CVV anywhere in the function (grep-verified).
- **Checkout RPCs (006):** `process_checkout_cash` (atomic cash sale with inventory decrement + audit), `create_checkout_intent` (cart + Paystack intent), `get_branch_catalog` / `get_catalog_delta` (server-side full + delta sync helpers). All `SECURITY DEFINER` with `user_belongs_to_business` checks and idempotent replay on duplicate keys.
- **Refunds, shifts, push, reorder (007–010):** Refund tables with `refunded_quantity` guard against over-refund; shifts with open/close RPCs and expected-cash computation; push subscriptions for alerts; per-branch `reorder_level` for Ledmi.
- **Sync protocol (docs/SYNC_PROTOCOL.md):** Auth flow, Hive box layout, full + delta catalog sync, online + offline checkout, idempotency key rules, offline queue schema, background sync scheduler, retry/backoff table, conflict resolution matrix, and resolved-dependencies section. RPC signatures match migrations.
- **Decisions & security docs:** 12 locked ADs; threat model and pre-pilot security checklist captured.

---

## 3. Gaps & Risks

### Critical (blocks Phase 1 exit)
1. **001 forward-references `branches(id)`** (`001_core_schema.sql:156`, `:298`). `inventory_logs` and `activity_logs` declare `branch_id UUID REFERENCES branches(id)`, but `branches` is created in `002_branch_model.sql`. A clean `supabase db reset` running 001 first will fail with `relation "branches" does not exist`. Either move `branches` creation into 001, or remove the FK from 001 and let 002/011 add it.
2. **`p_total_amount` units mismatch** between `docs/SYNC_PROTOCOL.md` §5.2/§10.2 (pesewas, e.g. `2500`) and `006_checkout_rpc.sql` `process_checkout_cash` (compares `v_computed_total != p_total_amount` where `v_computed_total` is GHS decimals). A client following the doc will hit `Total amount mismatch` on every cash sale. Pick one unit and align doc + code.

### High (security/correctness)
3. **`webhook_receipts` RLS policy is cross-business leaky** (`004_rls_policies.sql:469-473`). The table has no `business_id`; the policy grants `SELECT` to any user with `view_reports` in their *current* JWT business, so a user can read webhook receipts for **all** businesses. Add `business_id` to `webhook_receipts` (populated by the Edge Function from the matched intent) and scope the policy, or restrict reads to service role only.
4. **`close_shift` lacks caller verification** (`009_shifts.sql:35-82`). It is `SECURITY DEFINER` (bypasses RLS) but only checks the shift exists and is open — no `auth.uid() = cashier_id` and no `user_belongs_to_business` check. Any authenticated user can close any shift. Add ownership + membership guards like `open_shift` has.
5. **`process_refund` is not idempotent** (`007_refunds.sql:52`). No `p_idempotency_key` parameter; a retried refund call creates a second `refunds` row and restocks inventory twice. Add an idempotency key column/constraint and replay-on-duplicate semantics, mirroring `process_checkout_cash`.

### Medium
6. **`safe_finalize_sale` hardcodes `method='CARD'`** (`005_paystack_webhook_rpc.sql:145`). MoMo payments routed through Paystack will be recorded as `CARD` in the legacy `payments` table, corrupting dashboard reporting. Derive method from the intent/channel.
7. **RLS policies missing `WITH CHECK`** on `refunds` (`007:165-168`), `refund_items` (`007:171-177`), `shifts` (`009:29-32`), `push_subscriptions` (`008:22-25`). `FOR ALL` with only `USING` allows visibility scoping but does not validate new rows on INSERT/UPDATE, so a business member could insert rows referencing other businesses' parents (e.g. a `refund_items` row pointing at another business's `refund`). Add `WITH CHECK` clauses.
8. **`refunded_quantity` is not `SECURITY DEFINER`** (`007_refunds.sql:49`). Harmless under RLS but inconsistent with the rest of the helper set; callers may get empty results depending on context.
9. **`create_checkout_intent` status mismatch.** `SYNC_PROTOCOL.md` §7.2 says the intent is created with `status='pending'`, but `006_checkout_rpc.sql:335` sets `status='initiated'`. The `paystack-initiate` Edge Function correctly checks for `'initiated'` (`index.ts:161`), so the code is internally consistent — the doc is wrong. Update §7.2.
10. **`011_fix_activity_inventory_logs.sql` is redundant.** `001` already creates `activity_logs` and `inventory_logs` with `branch_id`, so the `IF NOT EXISTS` guards never fire. Not harmful, but it signals the migration sequence was edited after the fact; confirm the intended baseline.
11. **`current_business_id()` relies on a JWT `business_id` claim** (`003_auth_helpers.sql:24-31`) that SYNC_PROTOCOL §3.3 says is injected via headers/RPC args, not JWT. The claim path is only used by the `webhook_receipts` policy (gap #3). Either wire the claim in Supabase Auth or remove the dependency.

### Low
12. **`paystack-initiate` uses a synthetic email** `cashier-${userId}@ledgermind.app` (`index.ts:170`). Paystack requires an email; this works but bounces any customer receipt. Acceptable for MVP, flag for follow-up.
13. **`SECURITY.md` pre-pilot checklist is entirely unchecked** (`SECURITY.md:88-98`). Items 1, 3, 4 are effectively verifiable now — mark them.

---

## 4. Next 5 Prioritized Tasks

| # | Task | Owner IC | Acceptance Criteria |
|---|------|----------|---------------------|
| 1 | **Fix 001→002 branch FK ordering** so `supabase db reset` runs clean. | Backend Architect | `supabase db reset` applies 001–011 with zero errors on an empty database; no forward references remain in 001. |
| 2 | **Add `business_id` to `webhook_receipts` and re-scope RLS** to prevent cross-business reads. | Security/RLS Specialist | `webhook_receipts` has `business_id` populated by the Edge Function from the matched intent; policy requires `user_belongs_to_business(business_id)`; a user in business A cannot `SELECT` receipts for business B (verified by a test). |
| 3 | **Add ownership + membership guards to `close_shift`** and `WITH CHECK` to refund/shift/push RLS policies. | Security/RLS Specialist | `close_shift` raises unless `auth.uid() = p_cashier_id` and caller belongs to the shift's business; all `FOR ALL` policies include `WITH CHECK`; existing tests still pass. |
| 4 | **Make `process_refund` idempotent** and derive `method` from the intent in `safe_finalize_sale`. | Payment Engineer + Backend Architect | `process_refund` accepts `p_idempotency_key`, replays the existing refund on duplicate, and rejects key reuse with a different payload; `safe_finalize_sale` writes the correct `method` (card/momo/cash) into `payments`. |
| 5 | **Reconcile `p_total_amount` units** across `SYNC_PROTOCOL.md` and `006_checkout_rpc.sql`, and fix the §7.2 `status='pending'` vs `'initiated'` doc drift. | Sync Protocol Designer | Doc and code agree on pesewas-vs-GHS for `p_total_amount`; a sample cash sale from the doc's payload succeeds against the RPC; §7.2 reflects `status='initiated'`. |

---

## 5. Note to the Team

Team — I've gone through every migration, both Edge Functions, and the three core docs line by line, and the honest takeaway is this: the bones of this system are strong. The event-sourced payment ledger, the idempotency discipline, the branch-scoped RLS, and the sync protocol are exactly the right shape for an offline-first Ghanaian retail OS, and you should feel good about that. What's standing between us and a clean Phase 1 exit is a short, specific list — a migration ordering bug, one leaky policy, a couple of missing guards, and a units mismatch — none of which are architectural. Let's close the five tasks above this week so we can hand Devin a reset that runs clean and a security posture we'd defend in a pilot review. I'm proud of where this is; let's make it airtight.

— **Kwame Asante**, VP Engineering
