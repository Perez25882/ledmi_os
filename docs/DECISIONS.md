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
