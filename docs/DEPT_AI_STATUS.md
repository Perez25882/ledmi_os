# Ledmi AI — Department Status Report

**Author:** Dr. Selma Karim, VP AI & Analytics
**Date:** 2026-07-15
**Audience:** CEO (Devin), AI/Analytics Lead (agent_07)
**Scope:** Ledmi embedded AI assistant — design audit + implementation state vs. `docs/LEDMI_DESIGN.md`, `AGENTS.md`, `docs/MASTER_PLAN.md` Phase 5.

---

## 1. Component Status Table

| # | Component | Path / Spec | Completion % | Notes |
|---|---|---|---|---|
| 1 | Ledmi Design Doc | `docs/LEDMI_DESIGN.md` (842 lines) | 100% (spec) | Comprehensive: 3 insight types, mat-views, `ai_insights` table, confidence scoring, cadence, prompts, tool calls, NVIDIA NIM §5.4. Internally inconsistent on model name (see §4). |
| 2 | Chat API route | `ledgermindv1-main/app/api/ledmi/chat/route.ts` | 70% | Working POST; grounded system prompt built from real insights; NVIDIA NIM via `lib/nvidia-ai.ts`; heuristic keyword fallback when no API key. No tool-call execution, no conversation history passthrough, no `grounded_in` field in response. |
| 3 | Insights API route | `ledgermindv1-main/app/api/ledmi/insights/route.ts` | 65% | Working GET; RBAC gated (`canAccessPage("ai")`); calls `getInsights()` + `generateProactiveInsights()`. Computes insights on-the-fly in JS, not from materialized views. |
| 4 | NVIDIA NIM client | `ledgermindv1-main/lib/nvidia-ai.ts` | 80% | `askNVIDIA()` + `generateProactiveInsights()`; correct endpoint/model/env; temp 0.3; JSON-parse with heuristic fallback. No tool-call handling here (lives only in orphaned `ai-service.ts`). |
| 5 | Insights data layer | `ledgermindv1-main/lib/supabase/data/insights.ts` | 45% | Reorder = simple `quantity <= reorder_level` with `suggested_order = max(level*2 - qty, 10)` — NOT the velocity/safety-stock formula from design §3.1. Margin threshold = 10% (design says 15%). Anomalies = 3 hardcoded heuristic strings, no z-score. No confidence scores computed. |
| 6 | Ledmi chat panel (UI) | `ledgermindv1-main/components/ai-chat.tsx` | 75% | Floating "Ask Ledmi" button + panel; mounted in `app/dashboard/layout.tsx:43`; quick-starter prompts; fetches `/api/ledmi/insights` on open. Single-turn only (no persisted history). |
| 7 | Insights dashboard page | `ledgermindv1-main/app/dashboard/ai-insights/supabase/page.tsx` | 60% | Revenue/sales/reorder stat cards, proactive AI summary card, reorder & low-margin badges, "Ask Ledmi" box. Reads live from API. No anomaly chart, no feedback actions. |
| 8 | Insight card component | `ledgermindv1-main/components/dashboard/ai-insight-card.tsx` | 30% | Uses types `forecast/anomaly/recommendation/trend` — mismatches design enum `reorder/anomaly/margin/brief/trend`. "Mark as read" is a TODO stub (no endpoint). Not wired to any persisted `ai_insights` rows. |
| 9 | AI setup guide (UI) | `ledgermindv1-main/components/ai-setup-guide.tsx` | 10% | **Still advertises "Kimi (Moonshot AI)"** to users — contradicts actual NVIDIA NIM backend. Must be corrected. |
| 10 | Legacy AI service | `ledgermindv1-main/lib/ai-service.ts` | 0% (orphan) | Older NVIDIA integration with `add_inventory_item` / `update_stock_quantity` tool definitions. Not imported by any `/api/ledmi/*` route. Dead code — candidate for removal or consolidation. |
| 11 | `AIInsight` TypeScript type | `ledgermindv1-main/lib/supabase/types.ts:305-325` | 40% | Type defined (`reorder/anomaly/margin/trend/forecast/recommendation`) but no backing table exists in migrations. |
| 12 | `ai_insights` table (spec §6.1) | `infra/supabase/migrations/` | 0% | **Not implemented.** No migration creates `ai_insights`, its enums, indexes, or RLS. |
| 13 | Materialized views (spec §2.2) | `infra/supabase/migrations/` | 0% | **Not implemented.** No `mv_daily_sales`, `mv_stock_velocity`, or `v_inventory_snapshot`. |
| 14 | Daily brief cron (spec §4.1) | `infra/supabase/` | 0% | No `pg_cron` job, no scheduled Edge Function, no `ledmi-assistant` Edge Function. |
| 15 | Real-time sync trigger (spec §4.2) | `infra/supabase/migrations/` | 0% | No `trg_after_sync_batch`, no `ai_insight_jobs` queue table. |
| 16 | Feedback endpoint (spec §6.2) | `ledgermindv1-main/app/api/` | 0% | No `PATCH /api/ai/insights/{id}`; no `actioned/dismissed/snoozed` flow. |
| 17 | Push notification eligibility (spec §4.3) | `ledgermindv1-main/` | 0% | `push_eligible` boolean never emitted; `app/api/push/*` exists but not wired to insights. |
| 18 | Reorder threshold column | `infra/supabase/migrations/010_inventory_reorder_level.sql` | 100% | `inventory.reorder_level` added + indexed. Only AI-adjacent migration present. |

**Overall Ledmi implementation: ~35%.** Design is strong; backend persistence/aggregation layer is essentially absent; frontend has a working chat + insights surface but no persistence, feedback, or scheduling.

---

## 2. What's Specified vs. Implemented

### Specified (in `docs/LEDMI_DESIGN.md`)
- **3 insight types:** reorder (velocity + safety stock, 14-day horizon), anomaly (z-score ≥1.5/2.0/3.0), margin advisor (15% threshold, price bands).
- **Data prep:** `mv_daily_sales`, `mv_stock_velocity` (feature store), `v_inventory_snapshot`; daily 06:00 GMT refresh; concurrent refresh after sync.
- **Cadence:** daily morning brief per business (06:30 GMT via `pg_cron`/Edge Function); real-time critical-alert trigger after offline batch sync.
- **AI assistant:** Supabase Edge Function `ledmi-assistant` (preferred) or `POST /api/ai/ask`; system prompt with business snapshot; tool calls (`add_inventory_item`, `update_stock_quantity`) executed via Postgres RPC.
- **Persistence & feedback:** `ai_insights` table with enums, confidence score, `push_eligible`, status (`pending/actioned/dismissed/snoozed`); `PATCH` feedback endpoint; action-rate tuning loop.
- **Confidence scoring:** `1.0 - (stddev / (avg + 0.001))` clamped `[0.55, 0.99]`; suppress <0.50.
- **Cost control:** cached 10-min business snapshot, top-50 products, capped token budget.

### Implemented (in `ledgermindv1-main/` + `infra/supabase/`)
- `/api/ledmi/chat` and `/api/ledmi/insights` Next.js routes (server-side, NVIDIA NIM).
- `lib/nvidia-ai.ts` — NVIDIA NIM chat + proactive summary generation.
- `lib/supabase/data/insights.ts` — JS-computed reorder (threshold-only), margin (10%), today summary, heuristic anomaly strings.
- `components/ai-chat.tsx` — floating Ledmi chat panel in dashboard layout.
- `app/dashboard/ai-insights/supabase/page.tsx` — insights cards + ask box.
- `inventory.reorder_level` column (migration 010).
- RBAC guard on AI routes (`canAccessPage("ai")`).

### Not implemented
- `ai_insights` table, enums, RLS, indexes.
- All materialized views + refresh schedule.
- Daily brief cron / `ledmi-assistant` Edge Function.
- Real-time sync trigger + `ai_insight_jobs` queue.
- Velocity-based reorder formula, z-score anomaly detection, margin price bands.
- Confidence scores in the data layer.
- Feedback endpoint + action-rate loop.
- Push-notification eligibility emission.
- Tool-call execution in the live `/api/ledmi/chat` route.

---

## 3. Gaps & Risks

1. **No persistence layer.** Insights are recomputed on every page load with no `ai_insights` rows. Users cannot see history, act/dismiss, or feed back. This blocks the PRD success metric "AI insight click-through / action rate > 25%" (PRD §4) — there is nothing to measure.
2. **No aggregation layer.** Without `mv_daily_sales` / `mv_stock_velocity`, every insight request hits raw `sales`/`sale_items`/`inventory` in JS. This will not scale to 20 branches × 10K SKUs (Phase 6 load test 6.3) and makes the velocity/stddev-based formulas impossible.
3. **Insight formulas diverge from spec.** Reorder ignores sales velocity entirely (threshold-only); margin threshold is 10% vs. spec 15%; anomalies are heuristic strings, not statistical z-scores. Insights will be less accurate and less trustworthy than designed.
4. **No confidence scores.** Design mandates clamped confidence per insight; current data layer returns none. The `ai-insight-card.tsx` UI expects `confidence_score` but never receives it.
5. **No scheduling.** No daily brief, no real-time critical alerts after sync. Ledmi is purely reactive (on-demand page load) — contradicts the "proactive" goal in PRD §4.3 and Master Plan Phase 5.
6. **Dead/duplicate code.** `lib/ai-service.ts` (legacy, with tool definitions) is orphaned; `app/api/ai/chat/` is an empty directory. Risk of confusion and drift.
7. **Type drift.** `ai-insight-card.tsx` uses `forecast/recommendation/trend`; design + `types.ts` use `reorder/anomaly/margin/brief/trend`. Component will not render real insights correctly once persisted.

### Model inconsistency — NVIDIA NIM vs. Moonshot/Kimi  ⚠️ HIGH PRIORITY

The model identity is inconsistent across the source of truth:

| Source | Says | Path |
|---|---|---|
| `AGENTS.md` §3 Tech Stack | **NVIDIA NIM** via `/api/ledmi/*` | `AGENTS.md:53` |
| `AGENTS.md` §6 Env | `NVIDIA_API_KEY`, `NVIDIA_MODEL=meta/llama-3.1-8b-instruct` | `AGENTS.md:123-124` |
| `docs/MASTER_PLAN.md` Phase 5.4 | **Moonshot/Kimi** assistant | `docs/MASTER_PLAN.md:84` |
| `docs/LEDMI_DESIGN.md` §1 | Moonshot/Kimi is the LLM | `docs/LEDMI_DESIGN.md:15` |
| `docs/LEDMI_DESIGN.md` §5.1 | Edge Function calls Moonshot/Kimi | `docs/LEDMI_DESIGN.md:487` |
| `docs/LEDMI_DESIGN.md` §5.4 | **NVIDIA NIM** API integration details | `docs/LEDMI_DESIGN.md:582-615` |
| Actual code (`lib/nvidia-ai.ts`) | **NVIDIA NIM** (`integrate.api.nvidia.com`) | `lib/nvidia-ai.ts:4-6` |
| User-facing UI (`ai-setup-guide.tsx`) | **Kimi (Moonshot AI)** | `components/ai-setup-guide.tsx:13-15` |

**Resolution (recommended):** `AGENTS.md` is the locked team charter and the implemented reality is NVIDIA NIM. Standardize on **NVIDIA NIM** everywhere:
- Update `docs/MASTER_PLAN.md` Phase 5.4: "Integrate NVIDIA NIM (Llama 3.1) assistant with dashboard chat panel."
- Update `docs/LEDMI_DESIGN.md` §1 and §5.1: replace "Moonshot/Kimi" with "NVIDIA NIM (`meta/llama-3.1-8b-instruct`)".
- Update `components/ai-setup-guide.tsx`: replace "Kimi (Moonshot AI)" branding with "NVIDIA NIM" / "Ledmi AI".
- Keep `NVIDIA_API_KEY` / `NVIDIA_MODEL` env vars as-is (already correct in `AGENTS.md` and `.env.example`).

If the business later decides Kimi/Moonshot is preferred, make the model pluggable via env (`LEDMI_LLM_PROVIDER=nvidia|moonshot`) rather than hardcoding either — but do not split implementation now.

---

## 4. Next 5 Prioritized Tasks

**Owner:** AI/Analytics Lead (`agent_07`)

### Task A1 — Create `ai_insights` table + RLS migration
- **File:** `infra/supabase/migrations/012_ai_insights.sql`
- **Acceptance criteria:**
  - Creates `ai_insight_type` enum (`reorder, anomaly, margin, brief, trend`), `ai_insight_status` enum (`pending, actioned, dismissed, snoozed`), `ai_insights` table per design §6.1 with all columns + indexes.
  - RLS policies: business members can read their own insights; only service role / cron can insert.
  - Idempotent; applies cleanly on a fresh DB.

### Task A2 — Add materialized views + refresh schedule
- **File:** `infra/supabase/migrations/013_ledmi_aggregations.sql`
- **Acceptance criteria:**
  - Creates `mv_daily_sales`, `mv_stock_velocity`, `v_inventory_snapshot` exactly per design §2.2 with unique indexes.
  - Registers a `pg_cron` job (or documents the external scheduler) to `REFRESH MATERIALIZED VIEW CONCURRENTLY` daily at 06:00 GMT.
  - Idempotent; views refresh without error on a seeded DB.

### Task A3 — Rewrite `getInsights()` to use views + spec formulas + confidence
- **File:** `ledgermindv1-main/lib/supabase/data/insights.ts`
- **Acceptance criteria:**
  - Reorder reads from `mv_stock_velocity`; uses `days_until_stockout <= 7 OR current_stock <= reorder_threshold`; suggested qty = `(avg*14) + (1.65*stddev) - stock`; cap 10 per branch.
  - Anomaly computes z-score over 14-day rolling window; severity per design §3.2 thresholds.
  - Margin uses 15% threshold + 3-point category drop; emits suggested price band.
  - Every insight carries a `confidence_score` per design formula, clamped `[0.55, 0.99]`.
  - Inserts generated insights into `ai_insights` (dedupe by business+branch+type+data hash within 24h).

### Task A4 — Feedback endpoint + insight card wiring
- **Files:** `ledgermindv1-main/app/api/ledmi/insights/[id]/route.ts`, `components/dashboard/ai-insight-card.tsx`
- **Acceptance criteria:**
  - `PATCH /api/ledmi/insights/{id}` accepts `{ status: "actioned"|"dismissed"|"snoozed" }`, updates row, logs to `activity_logs`, enforces RLS + `actor_id`.
  - `ai-insight-card.tsx` uses the design enum types, renders real `ai_insights` rows, and calls the PATCH endpoint for action/dismiss/snooze.
  - Replaces the TODO "mark as read" stub with a working call.

### Task A5 — Resolve model inconsistency + remove dead code
- **Files:** `docs/MASTER_PLAN.md`, `docs/LEDMI_DESIGN.md`, `components/ai-setup-guide.tsx`, `lib/ai-service.ts`, `app/api/ai/chat/`
- **Acceptance criteria:**
  - All references to "Moonshot/Kimi" in master plan, design doc §1/§5.1, and `ai-setup-guide.tsx` replaced with "NVIDIA NIM" per §3 resolution above.
  - `lib/ai-service.ts` either deleted or consolidated into `lib/nvidia-ai.ts` (preserve tool-call definitions if still wanted).
  - Empty `app/api/ai/chat/` directory removed.
  - `npm run lint` passes; no broken imports.

---

## 5. Sign-off

Ledmi's design is genuinely excellent — grounded, actionable, and honest about cost. The team has shipped a real, working chat surface on NVIDIA NIM faster than I expected, and the grounding discipline (real numbers only) is already in the system prompt. That is the hard part done right.

What's missing is the spine: persistence, aggregation, and the statistical formulas that turn raw sales into trustworthy predictions. None of that is exotic — it's migrations and SQL — but it's the difference between a demo and a product our 10 Accra chains will rely on. Let's build the spine next, fix the model-name story so customers see one truth, and start measuring action rates. I'm confident in this team. Onward.

— **Dr. Selma Karim**, VP AI & Analytics
