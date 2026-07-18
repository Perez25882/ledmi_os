# LedgerMind OS — Architectural Decisions

**Status:** Locked for Phase 1  
**Owner:** Lead Engineer  
**Related:** `PRD.md`, `AGENTS.md`, `docs/MASTER_PLAN.md`

---

## AD-1: Supabase is the single backend

**Decision:** Use Supabase (Postgres, Auth, Edge Functions, Realtime) as the only backend for the MVP.

**Rationale:**
- The existing `database_architecture` is already designed for Postgres/Supabase.
- LedgerMind currently uses Firebase; the migration target is Supabase.
- One backend reduces sync complexity between dashboard and POS.

**Consequences:**
- LedgerMind dashboard must migrate off Firebase.
- Flutter POS depends on Supabase client and offline queue.
- All real-time sync uses Supabase Realtime or polling.

---

## AD-2: Offline-first Flutter POS

**Decision:** The Flutter POS must never block a sale due to lack of internet. Sales are captured locally and synced when online.

**Rationale:**
- Internet reliability is a core problem in the target market.
- Competitors (SellarPro, Bumpa) already market offline mode as a key feature.
- This is a major differentiator against Oval POS.

**Consequences:**
- Requires a robust local cache (Hive) and background sync engine.
- Requires idempotency keys and conflict resolution.
- Payment confirmation for MoMo/card still needs connectivity.

---

## AD-3: Paystack as the sole payment provider for MVP

**Decision:** Integrate Paystack only for card, MoMo, and webhooks. Hubtel/Flutterwave are documented fallbacks, not active integrations.

**Rationale:**
- Paystack supports card tokenization and MoMo in Ghana.
- Focusing on one provider reduces integration scope and webhook complexity.
- The team confirmed Paystack as the provider.

**Consequences:**
- Edge Function is Paystack-specific.
- If Paystack MoMo is unstable in Ghana, we may need Hubtel fallback quickly.

---

## AD-4: Event-sourced payment state

**Decision:** Use `payment_intents` + `payment_events` as the source of truth for payment state, keeping the legacy `payments` table for compatibility.

**Rationale:**
- Existing `database_architecture` already includes an event-sourced design.
- Immutable event ledger makes reconciliation and audit easier.
- Webhook idempotency is simpler with append-only events.

**Consequences:**
- The webhook Edge Function records events and calls `safe_finalize_sale`.
- Dashboard reads from `payment_status_projection` or helper functions.

---

## AD-5: Card data never touches our servers

**Decision:** Card numbers and expiry are extracted on-device by ML Kit and sent directly to Paystack. Our backend stores only the Paystack reference, last-4 digits, and brand.

**Rationale:**
- Minimizes PCI compliance scope.
- Avoids storing sensitive cardholder data.

**Consequences:**
- Card scanner module must be embedded in the Flutter app, not a separate upload step.
- The backend never accepts raw PAN fields.

---

## AD-6: Multi-tenant data model with branch scoping

**Decision:** Every table is scoped to `business_id`. Inventory, carts, sales, and invoices also include `branch_id` for multi-branch visibility.

**Rationale:**
- Target market is retail chains with multiple branches.
- Branch-level reporting and inventory are core requirements.

**Consequences:**
- All queries and RLS policies must include business/branch filters.
- POS selects a branch at login and passes `branch_id` in every request.

---

## AD-7: Proactive AI insights

**Decision:** Ledmi generates a daily morning brief and real-time alerts after sync. Insights are grounded in actual sales/inventory data.

**Rationale:**
- User wants AI to be proactive, not just on-demand.
- Scheduled insights are cheaper and more reliable than per-request LLM calls.
- Real-time alerts catch stockouts and anomalies as they happen.

**Consequences:**
- Requires daily aggregation job or materialized view.
- Requires `ai_insights` table with confidence and feedback fields.
- LLM is used for natural-language summary and recommendations, but numbers come from SQL.

---

## AD-8: GRA E-VAT deferred to post-pilot

**Decision:** Do not implement Ghana Revenue Authority E-VAT invoice formatting for the pilot.

**Rationale:**
- No tax advisor on the team to validate exact format.
- Pilot can run with standard receipts; tax compliance can be added later.
- Schema will keep tax/levy fields configurable.

**Consequences:**
- Invoices are immutable receipts but not GRA-compliant initially.
- A fast-follow feature after pilot will add levies, QR codes, and GRA export.

---

## AD-9: No bundled hardware at MVP launch

**Decision:** Provide a recommended hardware list but do not sell, bundle, or warranty hardware at launch.

**Rationale:**
- Hardware logistics and support would slow software iteration.
- Pilot customers in Accra can source hardware locally faster.
- We can validate hardware combinations before offering a bundle.

**Consequences:**
- POS must support common Bluetooth thermal printers and barcode scanners.
- A hardware bundle can become a revenue line after pilot.

---

## AD-10: Ghana first, Accra pilot

**Decision:** Launch pilot with 10 retail chains in Accra before expanding to Kumasi, Tamale, Nigeria, or Kenya.

**Rationale:**
- Concentrated feedback loop.
- Simplifies payment, compliance, and support.
- Reduces go-to-market complexity.

**Consequences:**
- UI copy, payment methods, and tax settings are Ghana-centric for MVP.
- Localization for other markets is post-MVP.

---

## AD-11: Separate RPCs for cash and Paystack checkout

**Decision:** Cash sales use `process_checkout_cash(...)`; Paystack card/MoMo sales use `create_checkout_intent(...)` and are finalized by the `paystack-webhook` Edge Function calling `safe_finalize_sale(...)`.

**Rationale:**
- Cash sales can be finalized immediately and do not need event-sourced payment state.
- Paystack sales require async webhook confirmation; separating intent creation from finalization lets the POS wait for the webhook without blocking the UI.
- `safe_finalize_sale` is idempotent and transactional, so duplicate webhooks cannot double-charge inventory.

**Consequences:**
- `SYNC_PROTOCOL.md` distinguishes the two flows and their payloads.
- Offline sales in Phase 3 must queue cash only; Paystack requires connectivity.

---

## AD-12: Branch-scoped operational tables with `NOT NULL branch_id`

**Decision:** After `002_branch_model.sql`, `inventory`, `carts`, `sales`, `invoices`, and `inventory_logs` all have `NOT NULL branch_id` columns with `ON DELETE CASCADE`.

**Rationale:**
- Every stock movement, cart, and sale must belong to a physical branch.
- `NOT NULL` prevents accidentally business-scoped writes that could leak across branches.
- `ON DELETE CASCADE` keeps foreign-key semantics simple; branches are normally soft-deleted via `deleted_at`.

**Consequences:**
- Onboarding must create at least one branch before any inventory or sale can exist.
- All RPCs and RLS policies must include `branch_id`.
- `LEDMI_DESIGN.md` was updated to reflect the actual migration rather than the original nullable assumption.

---

## AD-13: Wire amounts in pesewas (integer minor units)

**Decision:** All client→server amount parameters use **pesewas** (GHS × 100, integer `BIGINT`), not GHS decimals.

**Rationale:**
- Floats cause rounding drift in financial comparisons; integers are exact.
- The sync protocol already documented pesewas; the code was the outlier.
- Aligns Flutter POS, dashboard, and RPCs on one wire format.

**Consequences:**
- `process_checkout_cash.p_total_amount` and `create_checkout_intent.p_total_amount` are `BIGINT` (pesewas).
- Flutter `checkout_service.dart` converts `(total * 100).round()` before the RPC call.
- Storage in `payments.amount`, `payment_intents.amount`, `invoices` remains GHS decimals (server converts).
- `SYNC_PROTOCOL.md` §5.2/§10.2 updated to document pesewas consistently.

---

## AD-14: Derive payment method from Paystack channel, not hardcoded

**Decision:** `safe_finalize_sale` reads `data.channel` from the captured `payment_events.payload` and maps it to `payments.method` instead of hardcoding `'CARD'`.

**Rationale:**
- MoMo/USSD/bank-transfer payments were misrecorded as CARD, corrupting dashboard reporting.
- The channel is already in the webhook payload; no schema change or caller change needed.

**Consequences:**
- Mapping: `card`→CARD, `mobile_money`/`ussd`→MOMO, `bank_transfer`/`bank`/`bank_account`→BANK_TRANSFER, unknown→CARD (safe default).
- `safe_finalize_sale` signature unchanged — no Edge Function caller impact.
- Future: a first-class `channel` column on `payment_intents` would be cleaner (follow-up).

---

## AD-15: `webhook_receipts` scoped by `business_id`

**Decision:** Add `business_id` to `webhook_receipts` and scope the RLS SELECT policy to `business_id = current_business_id()`.

**Rationale:**
- The original policy leaked webhook receipts across all businesses to any user with `view_reports`.
- `business_id` is backfilled from the matched `payment_intent` on insert and on duplicate-replay.
- Nullable for orphan webhooks (transfers, unmatched retries); NULL-business receipts are service-role-only.

**Consequences:**
- Migration `012_webhook_receipts_business.sql` adds the column, backfill, FK, index, and replacement policy.
- `paystack-webhook/index.ts` populates `business_id` from the matched intent.
- No cross-business data leak.

---

## AD-16: Standardize AI model identity on NVIDIA NIM

**Decision:** NVIDIA NIM (`meta/llama-3.1-8b-instruct`) is the sole LLM for Ledmi for the MVP. All docs, UI, and code reference NVIDIA NIM, not Moonshot/Kimi.

**Rationale:**
- `AGENTS.md` (locked charter) and the actual code (`lib/nvidia-ai.ts`) both use NVIDIA NIM.
- `MASTER_PLAN.md` and `LEDMI_DESIGN.md` had stale Moonshot/Kimi references causing confusion.
- User-facing `ai-setup-guide.tsx` advertised Kimi — contradicted the backend.

**Consequences:**
- `MASTER_PLAN.md` Phase 5.4, `LEDMI_DESIGN.md` §1/§5.1/§5.3/§8.2, and `ai-setup-guide.tsx` all updated to NVIDIA NIM.
- `lib/ai-service.ts` consolidated to a tool-definition module (dead chat logic removed; unique tool schemas preserved).
- Empty `app/api/ai/chat/` removed.
- Future pluggability via `LEDMI_LLM_PROVIDER` env noted but not implemented in MVP.

---

## AD-17: Ledmi persistence + aggregation layer

**Decision:** Implement the `ai_insights` table (migration 013) and materialized views `mv_daily_sales` / `mv_stock_velocity` + `v_inventory_snapshot` (migration 014) as the spine of the Ledmi insight pipeline.

**Rationale:**
- Without persistence, insights were recomputed on every page load with no history, feedback, or action-rate measurement.
- Without aggregation, raw `sales`/`sale_items`/`inventory` queries in JS won't scale to 20 branches × 10K SKUs.
- The design spec (LEDMI_DESIGN §2.2, §6.1) already defined this; implementation was at 0%.

**Consequences:**
- `ai_insights` table with enums (`reorder/anomaly/margin/brief/trend`, `pending/actioned/dismissed/snoozed`), confidence scores, dedupe index, RLS (members read/update, service_role insert, no delete).
- Mat-views refreshed daily at 06:00 GMT via `pg_cron` (guarded) or external scheduler calling `refresh_ledmi_aggregations()`.
- `getInsights()` rewritten to use views + spec formulas (velocity reorder, z-score anomaly, 15% margin) + confidence + persist to `ai_insights`.
- PATCH `/api/ledmi/insights/{id}` feedback endpoint + `ai-insight-card.tsx` rewrite for action/dismiss/snooze.
- Mat-views inherit RLS from underlying tables (no direct RLS on mat-views).

---

## AD-18: Offline queue extended to refunds + Paystack intents + dead-letter

**Decision:** The Flutter offline queue now handles `sale`, `refund`, `paystackIntent`, and `inventoryAdjustment` op types. Exhausted ops are dead-lettered (not deleted).

**Rationale:**
- Cash-only queue blocked offline refunds and retriable card/MoMo intents (SYNC_PROTOCOL §5.1).
- Silent deletion of failed ops after 5 attempts was a data-loss risk.

**Consequences:**
- `offline_queue_service.dart` supports all op types with configurable max attempts per type.
- `refund_service.dart` enqueues when offline; drain replays the RPC.
- `deadLetterExhausted()` moves failed ops to `offline_queue_dead_letter` Hive box with reason + timestamp; `getDeadLetteredOps()`/`requeueFromDeadLetter()` exposed for future UI.
- Token-refresh failure stops sync, surfaces re-login signal, preserves the queue (SYNC_PROTOCOL §3.2).

---

## AD-19: Two-app architecture — Flutter POS + Next.js dashboard (Option A)

**Decision:** Keep the Flutter POS (cashier tool) and Next.js dashboard (owner/manager/accountant tool) as two separate apps. Sharpen RBAC *within* each app by role. Do NOT consolidate into a single web app.

**Rationale:**
- Offline-first checkout is the core moat (AD-2). A web/PWA app cannot reliably do Bluetooth thermal printing, native camera barcode scanning, or ML Kit card OCR on cheap Android devices — all required by the PRD.
- Consolidating into web-only would forfeit the offline moat and make us "Oval POS but cheaper" — a weaker company.
- Cashiers and owners have fundamentally different jobs: a cashier wants a fast, big-button checkout; an owner wants a multi-branch dashboard. One UI cannot serve both well.
- The two apps already exist and are 78–88% built; consolidation would be a large rewrite for negative value.

**Consequences:**
- Flutter POS = cashier (Adjoa) + branch manager (Kofi) operational tool. Offline checkout, hardware, shift management.
- Next.js dashboard = owner (Ama) + accountant (Daniel) + manager (Kofi) visibility tool. Multi-branch, Ledmi AI, reports, GRA export.
- RBAC is enforced within each app, not by merging them. Permission names are mirrored across both apps for consistency.
- A lightweight PWA view for managers checking today's numbers on their phone is a possible future addition, not a replacement.

---

## AD-20: Fold ML card scanner into Flutter POS; use Paystack hosted checkout

**Decision:** The standalone `flutter_ml_credit_card_data_extractor-main` app is folded into the Flutter POS as an embedded checkout step (path dependency `card_scanner` → `../flutter_ml_credit_card_data_extractor-main`). Card payments use Paystack's **hosted checkout** (authorization URL in webview), not direct API tokenization from the POS.

**Rationale:**
- One fewer app to maintain; the scanner was already wired via a `/card-scanner` route.
- Paystack hosted checkout keeps PCI scope minimal — the full PAN never enters our BLoC state, our backend, or our logs. The customer enters card details directly with Paystack.
- The scanner serves as a visual pre-fill/verification aid (last4 + expiry shown to cashier), not a PAN capture mechanism.
- This is safer than a literal reading of PRD US-4 (which imagined direct tokenization) while satisfying the payment-safety requirement (AGENTS.md §4: no full PAN/CVV stored or logged).

**Consequences:**
- `pubspec.yaml` path dependency on `card_scanner` confirmed; `CardScannedEvent` carries only `last4` + `expiry`.
- `billing_bloc._onCardScanned` stores only `cardLast4` + `cardExpiry` in state — never the PAN.
- The standalone scanner app is decommissioned as a separate deliverable (AD-19 fold).
- Future: if Paystack offers a mobile SDK tokenization path with acceptable PCI scope, we may revisit direct tokenization for faster checkout.
