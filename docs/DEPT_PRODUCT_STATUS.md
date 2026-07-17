# LedgerMind OS — Product Status Report

**Author:** Ama Osei, VP Product
**Date:** 2026-07-13
**Audience:** Flutter POS Lead (agent_05), Dashboard Lead (agent_06), CEO (Devin)
**Scope:** Audit of `flutter_billing_app-main/`, `ledgermindv1-main/`, and `flutter_ml_credit_card_data_extractor-main/` against `PRD.md` and `docs/MASTER_PLAN.md` Phase 1–3 exit criteria.

---

## 1. Completion Summary Table

| App / Area | Path | Completion % | Notes |
|---|---|---|---|
| **Flutter POS — deps** | `flutter_billing_app-main/pubspec.yaml` | 100% | All PRD-required deps present: `supabase_flutter ^2.8.0`, `hive ^2.2.3`, `mobile_scanner ^5.1.0`, `print_bluetooth_thermal ^1.1.2`, `go_router ^14.0.0`, `flutter_bloc ^8.1.5`, plus `connectivity_plus`, `uuid`, `flutter_dotenv`, `card_scanner` (path dep). |
| **Flutter POS — Supabase core** | `lib/core/supabase/` | 90% | `supabase_client.dart` (PKCE init from `.env`), `auth_service.dart` (signIn/signOut/session stream), `session_manager.dart` (Hive-backed business/branch/shift state). No token-refresh-failure handler per SYNC_PROTOCOL §3.2. |
| **Flutter POS — auth feature** | `lib/features/auth/presentation/pages/` | 95% | `login_page.dart` + `branch_selection_page.dart` load `user_business_roles` → `branches`, set session, trigger catalog sync. Solid. |
| **Flutter POS — billing feature** | `lib/features/billing/` | 75% | `checkout_service.dart` calls `process_checkout_cash` RPC + `create_checkout_intent` + `paystack-initiate` edge function + payment status polling. `billing_bloc.dart` handles scan/cart/discount/cash/card. `refund_service.dart` + `refund_page.dart` call `process_refund` RPC. `shift_service.dart` open/close + summary. **Gap:** MoMo button exists in `checkout_page.dart` but no MoMo flow; card path only captures last4, no Paystack tokenization. |
| **Flutter POS — product feature** | `lib/features/product/` | 70% | `product_repository_impl.dart` is Hive-only (no Supabase push, correct per server-wins rule). List/add/edit pages exist. **Gap:** `product_list_page.dart` still renders `₹` and India-centric hints; not Ghana-localized. |
| **Flutter POS — sync feature** | `lib/features/sync/data/services/` | 65% | `offline_queue_service.dart` (Hive queue, idempotency keys, max 5 attempts, connectivity stream), `offline_sync_service.dart` (drains queue on reconnect), `supabase_sync_service.dart` (full catalog refresh). **Gaps:** No delta sync (`get_catalog_delta`), no Realtime subscription, offline queue only handles cash sales (no refund/MoMo offline), `clearCompleted` deletes failed ops silently. |
| **Flutter POS — shop feature** | `lib/features/shop/` | 40% | `shop_details_page.dart` is local-only, India-centric (UPI ID, "Salem" address hints). Not wired to Supabase `businesses`/`branches`. Needs Ghana localization (MoMo numbers, GHS, GRA fields). |
| **Flutter POS — settings feature** | `lib/features/settings/` | 85% | `settings_page.dart` + `printer_bloc` manage Bluetooth thermal printer connection via `print_bluetooth_thermal`. Functional. |
| **Flutter POS — routing/DI** | `lib/config/routes/app_routes.dart`, `lib/core/service_locator.dart`, `lib/main.dart` | 95% | go_router with auth+branch redirect, `OfflineSyncService.startListening()` wired in `main.dart`, get_it DI. Clean. |
| **Card scanner module** | `flutter_ml_credit_card_data_extractor-main/` | 80% | `lib/pages/scanner_page.dart` uses `google_mlkit_text_recognition` + camera, regex extracts card number + expiry, returns `{cardNumber, expiryDate}` via `Navigator.pop`. Wired into checkout via `card_scanner_page.dart` → `checkout_page.dart::_buildCardScannerPanel` (`context.push('/card-scanner')`). **Gap:** Only last4 + expiry surfaced; no Paystack tokenization call — PRD US-4 requires card data go directly to Paystack over TLS. |
| **Dashboard — deps** | `ledgermindv1-main/package.json` | 85% | `name: ledgermind-supabase`, `next ^16.1.6`, `react ^18`, `tailwind ^4`, full Radix suite, `@supabase/ssr ^0.12.1`, `@supabase/supabase-js ^2.109.0`, `recharts`, `web-push`. **Risk:** `firebase ^12.10.0` + `firebase-admin ^13.7.0` still present — migration not fully clean. |
| **Dashboard — Supabase clients** | `lib/supabase/` | 95% | `server.ts` (service-role + user SSR client), `browser.ts`, `middleware.ts` (session refresh + route guards), `permissions.ts` (RBAC page matrix), `types.ts`. Clean SSR/CSR split per AGENTS §4. |
| **Dashboard — auth pages** | `app/auth/` | 95% | `sign-in`, `sign-up`, `sign-up-success`, `callback`, `error`, `login`. Password + Google OAuth. Uses `createClient()` browser client. |
| **Dashboard — data layer** | `lib/supabase/data/` | 90% | `catalog.ts`, `inventory.ts`, `sales.ts`, `insights.ts`, `refunds.ts`, `shifts.ts`, `push.ts`, `user-context.ts`. **Risk:** Several files use `createServiceClient()` (bypasses RLS) for reads — should use user-scoped client where possible. |
| **Dashboard — overview** | `app/dashboard/overview/page.tsx` | 90% | Today's revenue, sales count, low-stock, branch performance table, Ledmi proactive insight card. Grounded in real data. |
| **Dashboard — sales** | `app/dashboard/sales/page.tsx` | 80% | Sales ledger with branch/date filter, CSV export, totals. **Gap:** `cashier_email` hardcoded `"-"` (no join to `auth.users`). |
| **Dashboard — inventory** | `app/dashboard/inventory/supabase/page.tsx` | 90% | Live stock table, low/out alerts, total value, Realtime component. `app/dashboard/inventory/page.tsx` redirects to supabase variant. |
| **Dashboard — catalog** | `app/dashboard/catalog/page.tsx` | 90% | Product + category CRUD via server actions (`actions.ts`). Owner/manager gated. |
| **Dashboard — refunds/shifts/users/settings/reports** | `app/dashboard/{refunds,shifts,users,settings,reports}/` | 75% | Pages + actions exist for refunds, users, shifts. Reports page present. Settings + system + subscription + logs + ai-insights pages present. Coverage broad; depth unverified per-page. |
| **Dashboard — Ledmi AI** | `components/ai-chat.tsx`, `app/api/ledmi/{chat,insights}/route.ts`, `lib/nvidia-ai.ts`, `lib/supabase/data/insights.ts` | 85% | Floating chat panel in `dashboard/layout.tsx`, grounded system prompt (sales/reorder/margin/top products), NVIDIA NIM call with rule-based fallback. Proactive insights on overview. Meets PRD §5.4 + §9 grounding principle. |
| **Dashboard — onboarding** | `app/onboarding/`, `app/dashboard/onboarding/`, `app/api/onboarding/{create-business,seed-demo}/` | 85% | Business creation + demo seed endpoints. Redirects from layout when no context. |
| **Dashboard — push** | `app/api/push/{send,subscribe}/`, `components/push-notifications.tsx` | 70% | web-push integration present; pilot-critical alert channel scaffolded. |

**Weighted overall: Flutter POS ~78%, Dashboard ~88%, Card scanner ~80%.**

---

## 2. What's Done

### Flutter POS (`flutter_billing_app-main/`)
- Supabase bootstrap complete: `lib/core/supabase/supabase_client.dart` initializes with PKCE, env-driven; `auth_service.dart` + `session_manager.dart` persist business/branch/shift in Hive.
- Auth flow: `login_page.dart` → `branch_selection_page.dart` loads `user_business_roles` + `branches`, sets session, triggers `SupabaseSyncService.syncCatalog()`.
- Online checkout: `checkout_service.dart` calls `process_checkout_cash` and `create_checkout_intent` RPCs, invokes `paystack-initiate` edge function, polls `payment_intents.status`.
- Offline queue: `offline_queue_service.dart` enqueues sales with UUID idempotency keys, 5-attempt cap, connectivity stream; `offline_sync_service.dart` drains on reconnect and is started in `main.dart`.
- Barcode scanning: `home_page.dart` uses `mobile_scanner` with cooldown + haptic feedback.
- Receipt printing: `PrinterHelper` + `printer_bloc` drive `print_bluetooth_thermal`; receipt footer marks offline-pending sales.
- Refunds: `refund_service.dart` calls `process_refund` RPC with line-item selection and reason.
- Shifts: `shift_service.dart` open/close + summary aggregation.
- Card scanner wired: `card_scanner` path dep, `/card-scanner` route, `checkout_page._buildCardScannerPanel` consumes scan result.

### Dashboard (`ledgermindv1-main/`)
- Supabase migration largely complete: `lib/supabase/{server,browser,middleware,permissions,types}.ts` with proper SSR/CSR split and RBAC page guard matrix.
- Auth: password + Google OAuth, session middleware, protected `/dashboard` redirect.
- Pages: overview, sales (filter + CSV export), inventory (Realtime), catalog (CRUD), refunds, shifts, users, settings, reports, ai-insights, logs, system, subscription, onboarding.
- Ledmi AI: floating chat (`components/ai-chat.tsx`) grounded in `lib/supabase/data/insights.ts` (reorder, low margin, top products, anomalies); NVIDIA NIM via `lib/nvidia-ai.ts` with rule-based fallback; proactive insight card on overview.
- Data layer: `lib/supabase/data/*` covers catalog, inventory, sales, insights, refunds, shifts, push, user-context.
- Onboarding: `create-business` + `seed-demo` API routes.

### Card Scanner (`flutter_ml_credit_card_data_extractor-main/`)
- `lib/pages/scanner_page.dart` uses `google_mlkit_text_recognition` + camera stream, regex extracts 13–16 digit card number + MM/YY expiry, haptic confirmation, returns result map.
- Exposed as `card_scanner` package, consumed by POS via path dependency.

---

## 3. Gaps & Risks

### P0 — Blocks MVP loop
1. **Card scanner not tokenizing via Paystack** (`checkout_page.dart` L219–235). PRD US-4 requires card data go directly to Paystack over TLS; currently only last4 + expiry are displayed. No `paystack-initiate` call uses scanned card data. **Owner: Flutter POS Lead.**
2. **MoMo payment flow missing** (`checkout_page.dart` L208–213). Button exists, no handler. PRD §8.1 POS-4 requires MTN/Vodafone/AirtelTigo MoMo via Paystack. **Owner: Flutter POS Lead.**
3. **Firebase dependencies still in dashboard** (`package.json` L50–51). `firebase` + `firebase-admin` present alongside Supabase — migration incomplete, bundle bloat, potential auth-path confusion. **Owner: Dashboard Lead.**

### P1 — Quality / compliance
4. **Offline queue only handles cash sales** (`offline_sync_service.dart` L28). No offline refund queue, no offline MoMo/card intent retry. SYNC_PROTOCOL §5.1 defines `queued` for all sale types. **Owner: Flutter POS Lead.**
5. **No delta sync** (`supabase_sync_service.dart` does full `productBox.clear()` + reload). SYNC_PROTOCOL §4.3 mandates `get_catalog_delta` polling + optional Realtime. Will not scale to 10K SKUs. **Owner: Flutter POS Lead.**
6. **Dashboard reads bypass RLS** (`lib/supabase/data/sales.ts`, `inventory.ts`, `insights.ts` use `createServiceClient()`). AGENTS §4 requires RLS everywhere; service-role use must be justified and audited. **Owner: Dashboard Lead.**
7. **`cashier_email` hardcoded `"-"`** in sales ledger (`lib/supabase/data/sales.ts` L65). PRD §8.2 DASH-4 requires drill-down by cashier. **Owner: Dashboard Lead.**

### P2 — Localization / polish
8. **Flutter shop + product UI still India-centric** (`shop_details_page.dart` UPI ID field, "Salem" hints; `product_list_page.dart` renders `₹`). Ghana MVP needs GHS, MoMo numbers, GRA fields. **Owner: Flutter POS Lead.**
9. **No token-refresh-failure handler** (`auth_service.dart` lacks SYNC_PROTOCOL §3.2 fallback: stop sync, show login, preserve queue). **Owner: Flutter POS Lead.**
10. **`clearCompleted` silently deletes failed ops** (`offline_queue_service.dart` L120–127). Failed sales vanish after 5 attempts — data-loss risk. Needs dead-letter + UI surfacing. **Owner: Flutter POS Lead.**

---

## 4. Next 5 Prioritized Tasks

### Task 1 — Wire card scanner into Paystack tokenization
**Owner:** Flutter POS Lead
**Files:** `lib/features/billing/presentation/pages/checkout_page.dart`, `lib/features/billing/data/services/checkout_service.dart`
**Acceptance criteria:**
- After scan, card number + expiry are passed to `paystack-initiate` edge function (or Paystack SDK) over TLS.
- POS stores only last4 + reference; no full PAN/CVV persisted in Hive or logs (AGENTS §5.4).
- End-to-end card checkout completes against Paystack test key; receipt prints.
- `flutter analyze` passes.

### Task 2 — Implement MoMo checkout flow
**Owner:** Flutter POS Lead
**Files:** `lib/features/billing/presentation/bloc/billing_bloc.dart`, `lib/features/billing/data/services/checkout_service.dart`, `checkout_page.dart`
**Acceptance criteria:**
- MoMo payment method triggers `create_checkout_intent` with `p_method: 'momo'` and Paystack MoMo charge.
- Cashier can select MTN / Vodafone / AirtelTigo; customer phone number captured.
- Status polling finalizes sale; receipt prints.
- Offline MoMo attempts are queued with idempotency (extend `OfflineQueueService` op types).

### Task 3 — Remove Firebase + finalize Supabase-only dashboard
**Owner:** Dashboard Lead
**Files:** `package.json`, any residual `lib/firebase*` imports, `app/api/**` routes
**Acceptance criteria:**
- `firebase` and `firebase-admin` removed from `package.json`; `npm install` + `npm run lint` + `next build` succeed.
- No Firebase imports remain in `app/`, `components/`, `lib/`.
- Auth, data reads, and push notifications use Supabase exclusively.
- Document residual removal in `TASK_REPORT.md`.

### Task 4 — Implement delta sync + Realtime subscription
**Owner:** Flutter POS Lead
**Files:** `lib/features/sync/data/services/supabase_sync_service.dart`, new delta RPC client
**Acceptance criteria:**
- `syncCatalog()` uses `get_catalog_delta(p_since)` with `sync_meta.last_product_sync_at` cursor; no full clear unless first login.
- Subscribes to Realtime channel `business:{id}:branch:{id}:catalog` when online; falls back to 60s polling.
- Soft-deleted products removed from Hive; cart-in-conflict alerts per SYNC_PROTOCOL §4.4.
- Verified with 1K+ product fixture.

### Task 5 — Move dashboard reads to RLS-respecting user client
**Owner:** Dashboard Lead
**Files:** `lib/supabase/data/sales.ts`, `inventory.ts`, `insights.ts`, `refunds.ts`, `shifts.ts`
**Acceptance criteria:**
- All read paths use `createServerClientForUser()` unless an explicit admin override is documented.
- `cashier_email` resolved via join to `auth.users` or `user_business_roles` (fixes sales ledger).
- RLS policies verified to return expected rows for owner/manager/cashier/accountant roles.
- `npm run lint` + `next build` pass.

---

## 5. Sign-off

Leads —

This is a strong foundation. The Flutter POS has a real offline queue with idempotency, a working cash checkout RPC, Bluetooth printing, and the card scanner is physically wired into the checkout screen — that is more than most Ghanaian POS projects have after a year. The dashboard is live on Supabase with RBAC guards, a grounded Ledmi chat, and branch-aware inventory. You both delivered.

Now the hard part: closing the loop. **Flutter POS Lead** — Tasks 1, 2, 4 are the difference between a demo and a product. No Paystack tokenization and no MoMo means we cannot prove the PRD loop in Accra. **Dashboard Lead** — Task 3 is housekeeping we owe the CEO; Task 5 is a security commitment from AGENTS §4. RLS is not optional.

Pick one task, own it end-to-end, write the `TASK_REPORT.md`, and ping me when acceptance criteria are met. I will unblock anything that crosses workspaces.

We are building the OS that lets African chains sell offline, see everything, and decide smarter. Let's finish Phase 1 strong.

— **Ama**
VP Product, LedgerMind OS
