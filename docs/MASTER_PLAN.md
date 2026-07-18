# LedgerMind OS — Master Implementation Plan

**Locked PRD:** `C:\Users\DELL\Desktop\POS\PRD.md`  
**Team charter:** `C:\Users\DELL\Desktop\POS\AGENTS.md`  
**Goal:** Build MVP foundation autonomously and prepare for integration.

---

## Phase 1 — Foundation (Backend, Auth, Sync Protocol, POS Bootstrap)
**Target:** All Phase 1 deliverables complete before any agent starts Phase 2.

| # | Task | Owner | Deliverable | Success Criteria |
|---|---|---|---|---|
| 1.1 | **MVP Supabase Schema** | `agent_01` Backend Architect | `infra/supabase/migrations/001_core_schema.sql`, `002_branch_model.sql` | Idempotent migrations creating businesses, branches, users/roles, categories, suppliers, products, inventory, inventory_logs, carts, cart_items, invoices, sales, sale_items, payments, payment_intents, payment_events, webhook_receipts, activity_logs. Includes branch-level inventory. |
| 1.2 | **Paystack Webhook Edge Function** | `agent_02` Payment Engineer | `infra/supabase/functions/paystack-webhook/index.ts` + `deno.jsonc` | Verifies HMAC-SHA512, stores webhook receipt, inserts payment_events, finalizes sale via RPC, idempotent, logs errors. Includes local test script. |
| 1.3 | **Auth, RBAC & RLS** | `agent_03` Security/RLS Specialist | `infra/supabase/migrations/003_auth_helpers.sql`, `004_rls_policies.sql`, `seed/001_default_roles.sql` | Role helpers (`user_belongs_to_business`, `user_has_permission`, `user_is_owner`), RLS on all tables, default owner/manager/cashier/accountant roles. |
| 1.4 | **Flutter ↔ Supabase Sync Protocol** | `agent_04` Sync Protocol Designer | `docs/SYNC_PROTOCOL.md` | Defines auth flow, product sync, offline sale queue, conflict resolution, idempotency, error retry, payload schemas, RPC signatures. |
| 1.5 | **Flutter POS Bootstrap** | `agent_05` Flutter POS Lead | Code changes in `flutter_billing_app-main/lib/` | Adds `supabase_flutter`, auth/login screens, business/branch selection, product sync service using Hive, basic online checkout calling Supabase. |
| 1.6 | **Dashboard Supabase Migration Prep** | `agent_06` Dashboard Lead | `ledgermindv1-main/lib/supabase/` | Adds `@supabase/supabase-js`, removes Firebase-only dependency paths, creates auth wrapper, server/browser clients, types from schema. |
| 1.7 | **Environment & Dev Onboarding** | `agent_07` DevOps/Setup Lead | `.env.example` files, `README-INTEGRATION.md` | All apps have env templates, run instructions, dependency versions, hardware list. |
| 1.8 | **AI Insight Design** | `agent_07` AI Lead | `docs/LEDMI_DESIGN.md` | Defines data aggregations, insight types (reorder, anomaly, margin), prompt templates, API route, schedule/trigger logic. |
| 1.9 | **Lead Review & Merge** | Lead (Devin) | `docs/DECISIONS.md`, merged Phase 1 branch/folder | All agent outputs reviewed, conflicts resolved, schema unified, tests pass, Phase 2 ready. |

### Phase 1 Exit Criteria
- `supabase db reset` equivalent (local/test) applies all migrations without error.
- Paystack webhook function compiles and test script demonstrates HMAC verification and idempotency.
- Flutter app can log in, select a branch, and sync product catalog from Supabase.
- Dashboard can initialize Supabase client and read a business context.
- `docs/SYNC_PROTOCOL.md` is approved by lead and matches schema.

---

## Phase 2 — Core POS Online (Weeks 4–7)
**Goal:** A working online checkout on Android and iOS.

| # | Task | Owner |
|---|---|---|
| 2.1 | Product search, cart, discounts, and checkout UI | `agent_05` |
| 2.2 | Paystack charge initialization from Flutter (MoMo + card) | `agent_02` + `agent_05` |
| 2.3 | Receipt generation and Bluetooth thermal printing | `agent_05` |
| 2.4 | Cashier shift open/close and end-of-day report | `agent_05` |
| 2.5 | Sales ledger and inventory update RPC | `agent_01` + `agent_02` |
| 2.6 | Dashboard inventory view connected to live data | `agent_06` |
| 2.7 | Security review of checkout flow | `agent_03` |

---

## Phase 3 — Offline Sync & Card Scanning (Weeks 8–11)
**Goal:** POS never stops selling when offline.

| # | Task | Owner |
|---|---|---|
| 3.1 | Hive offline queue engine per SYNC_PROTOCOL | `agent_05` |
| 3.2 | Background sync with idempotency and conflict handling | `agent_05` + `agent_04` |
| 3.3 | Integrate ML credit-card scanner into checkout (Paystack tokenization) | `agent_05` |
| 3.4 | Refunds and returns online + offline | `agent_05` |
| 3.5 | Edge-case testing: network flapping, duplicate sync, large queues | `agent_04` |

---

## Phase 4 — Dashboard on Supabase (Weeks 12–15)
**Goal:** Full back-office experience on Supabase.

| # | Task | Owner |
|---|---|---|
| 4.1 | Migrate auth and remaining data reads/writes from Firebase to Supabase | `agent_06` |
| 4.2 | Business onboarding, branch creation, user invitations | `agent_06` |
| 4.3 | Product catalog, inventory, suppliers CRUD | `agent_06` |
| 4.4 | Sales ledger with filters and drill-down | `agent_06` |
| 4.5 | Multi-branch dashboard: revenue, margins, top products | `agent_06` |
| 4.6 | Invoice / receipt ledger export (CSV/PDF) | `agent_06` |
| 4.7 | Role-based menu visibility and guards | `agent_03` + `agent_06` |

---

## Phase 5 — Ledmi AI (Weeks 16–19)
**Goal:** Proactive, grounded AI insights.

| # | Task | Owner |
|---|---|---|
| 5.1 | Daily aggregation materialized view or scheduled function | `agent_07` |
| 5.2 | Reorder recommendation algorithm and API | `agent_07` |
| 5.3 | Anomaly detection and margin advisor | `agent_07` |
| 5.4 | Integrate NVIDIA NIM (Llama 3.1) assistant with dashboard chat panel | `agent_07` |
| 5.5 | Push notification service for critical alerts | `agent_07` |
| 5.6 | Insight feedback loop and confidence scoring | `agent_07` |

---

## Phase 6 — Pilot Hardening (Weeks 20–24)
**Goal:** 10 Accra chains live and stable.

| # | Task | Owner |
|---|---|---|
| 6.1 | Pilot onboarding scripts and support runbook | Lead + `agent_07` |
| 6.2 | Sync conflict resolution and reconciliation UI | `agent_04` + `agent_05` |
| 6.3 | Performance testing with 20 branches, 10K SKUs | `agent_01` |
| 6.4 | Security hardening and penetration checklist | `agent_03` |
| 6.5 | Documentation, training videos, launch site | Lead |
| 6.6 | Go/no-go decision for public launch | Team |

---

## Immediate Autonomous Tasks for Phase 1

The following tasks can be started in parallel **right now**:

1. **Backend Architect** → produce MVP schema migrations.
2. **Payment Engineer** → produce Paystack webhook Edge Function.
3. **Security & RLS Specialist** → produce auth helpers, RLS policies, seed roles.
4. **Sync Protocol Designer** → write `docs/SYNC_PROTOCOL.md`.
5. **Flutter POS Lead** → bootstrap Flutter app with Supabase auth and product sync.
6. **Dashboard Lead** → prep LedgerMind dashboard for Supabase migration.
7. **AI / Analytics Lead** → design Ledmi insight pipeline in `docs/LEDMI_DESIGN.md`.

Each agent must read `PRD.md` and `AGENTS.md`, work only in their assigned workspace, and write a `TASK_REPORT.md` when done.

---

## Lead Checkpoint cadence

- **After each Phase 1 task:** Agent submits `TASK_REPORT.md`.
- **Lead review:** Devin inspects outputs, resolves cross-file conflicts, updates `docs/DECISIONS.md`, and marks Phase 1 exit criteria.
- **No Phase 2 work starts until Phase 1 exit criteria are met.**

---

**This plan is locked. Team, you are cleared to start Phase 1.**
