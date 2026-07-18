# LedgerMind OS — Team Charter & Engineering Playbook

**Project:** LedgerMind OS — AI-Powered Retail Operating System for African Chains  
**Reference docs:** `PRD.md`, `RESEARCH.md`  
**Root workspace:** `C:\Users\DELL\Desktop\POS`  
**Status:** PRD locked. Phase 1 foundation in progress.

---

## 1. Mission

Build a unified, offline-first, AI-powered retail operating system. The MVP must prove this loop for 10 Ghanaian retail chains in Accra:

> **Offline sale → Paystack payment → inventory update → LedgerMind dashboard → Ledmi AI insight.**

We will do this by integrating and extending the existing codebases, not by starting from scratch.

---

## 2. Repository Layout

```text
C:\Users\DELL\Desktop\POS
├── AGENTS.md                    <-- you are here
├── PRD.md                       <-- locked product requirements
├── RESEARCH.md                  <-- competitive research
├── flutter_billing_app-main     <-- Flutter POS (package: billing_app)
├── ledgermindv1-main            <-- Next.js dashboard (name: ledgermind-supabase)
├── database_architecture        <-- existing Supabase SQL schema (reference only)
├── docs/                        <-- architecture, protocols, decisions
│   ├── MASTER_PLAN.md
│   ├── SYNC_PROTOCOL.md
│   ├── SECURITY.md
│   └── DECISIONS.md
└── infra/                       <-- deployment-ready infrastructure code
    └── supabase/
        ├── migrations/          <-- ordered SQL migrations (001_, 002_, etc.)
        ├── seed/                <-- seed scripts for roles and test data
        └── functions/           <-- Supabase Edge Functions
            └── paystack-webhook/
```

---

## 3. Tech Stack

| Layer | Technology |
|---|---|
| Backend / Database | Supabase (Postgres 15+, Auth, Edge Functions, Realtime) |
| Mobile POS | Flutter 3.x, BLoC, Hive, go_router, mobile_scanner, print_bluetooth_thermal, supabase_flutter |
| Dashboard | Next.js 16, React 18, TypeScript, Tailwind CSS, Radix/shadcn UI, supabase-js |
| AI | NVIDIA NIM via server-side `/api/ledmi/*` routes |
| Payments | Paystack (primary and only provider for MVP) |
| Offline sync | Hive local cache + Supabase client + idempotency keys |

---

## 4. Coding Standards

### General
- No hardcoded secrets. Everything lives in environment variables.
- All database schema changes go through ordered migrations in `infra/supabase/migrations/`.
- Every table must have RLS policies. No exceptions.
- Every sale, payment, and inventory mutation must be auditable.
- Write compact, idiomatic code. Do not add explanatory comments unless the logic is genuinely complex.
- Error handling: handle errors at the right boundary, but avoid wrapping every line in try/catch.

### Flutter
- Use the existing BLoC pattern already in the app.
- Prefer immutable state classes; avoid freezed unless already adopted.
- Keep UI code in `lib/presentation/` or existing equivalent.
- Local models mirror Supabase rows but include `toJson()` / `fromJson()` and `idempotencyKey` fields.

### Next.js
- Server-side data fetching via Supabase server client.
- Client-side mutations via Supabase browser client + optimistic updates.
- Keep UI components under `components/ui/` and pages under `app/`.
- Use TypeScript strict mode.

### SQL
- Migrations must be idempotent (`CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE`, `IF NOT EXISTS` for indexes/functions).
- One logical change per migration file, prefixed with `001_`, `002_`, etc.
- Keep `database_architecture/` read-only as reference; MVP lives in `infra/supabase/migrations/`.

---

## 5. Definition of Done

Before any agent marks a task complete, the following must be true:

1. **Compiles / lints cleanly:** `flutter analyze` or `npm run lint` passes for the changed project.
2. **Migrations are idempotent:** Can be applied repeatedly without errors.
3. **Security reviewed:** RLS policies or auth checks are in place for every touched table.
4. **Payment safety:** No full PAN/CVV is stored or logged.
5. **Documented:** A `TASK_REPORT.md` is written in the agent’s work directory summarizing changes, decisions, and blockers.
6. **No regressions:** Existing tests still pass. If tests do not exist for critical logic, add them.
7. **No cross-agent file conflicts:** Agent does not edit another agent’s assigned files without coordination through the lead.

---

## 6. Environment Variables

### Shared
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

### Flutter POS
```env
SUPABASE_URL=
SUPABASE_ANON_KEY=
PAYSTACK_PUBLIC_KEY=pk_test_...
```

### Dashboard
```env
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
NVIDIA_API_KEY=nvapi-...
NVIDIA_MODEL=meta/llama-3.1-8b-instruct
PAYSTACK_SECRET_KEY=sk_test_...
PAYSTACK_WEBHOOK_SECRET=whsec_...
```

### Edge Functions
```env
PAYSTACK_SECRET_KEY=sk_test_...
PAYSTACK_WEBHOOK_SECRET=whsec_...
```

Create `.env.example` files in each app root. Never commit `.env` files.

---

## 7. Team Roles & Responsibilities

| Role | Agent | Current Focus | Workspace |
|---|---|---|---|
| **Lead** | Devin | coordination, review, conflict resolution, final merge | root |
| **Backend Architect** | agent_01 | MVP Supabase schema, migrations, branch model | `infra/supabase/migrations/` |
| **Payment Engineer** | agent_02 | Paystack webhook Edge Function, payment_intents/events flow | `infra/supabase/functions/paystack-webhook/` |
| **Security & RLS Specialist** | agent_03 | Auth, RBAC, RLS policies, audit helpers | `infra/supabase/migrations/` |
| **Sync Protocol Designer** | agent_04 | Flutter ↔ Supabase sync API contract | `docs/SYNC_PROTOCOL.md` |
| **Flutter POS Lead** | agent_05 | supabase_flutter integration, auth, product sync | `flutter_billing_app-main/` |
| **Dashboard Lead** | agent_06 | Migrate LedgerMind to Supabase, auth layer | `ledgermindv1-main/` |
| **AI / Analytics Lead** | agent_07 | Ledmi insight pipeline, data aggregations | `docs/LEDMI_DESIGN.md`, dashboard code |

---

## 8. Communication Protocol

1. **Read first:** Every agent reads `PRD.md` and `AGENTS.md` before starting.
2. **Work in your folder:** Do not modify files outside your assigned workspace unless explicitly asked by the lead.
3. **Report in writing:** When done, create a `TASK_REPORT.md` in your workspace with:
   - What was completed
   - Files changed
   - Key decisions and trade-offs
   - Blockers or questions for the lead
   - Suggested next task
4. **No silent edits:** If you rename or move a file another agent depends on, report it immediately.
5. **No pushing to git:** The lead will review, squash, and commit.

---

## 9. Key Engineering Principles

1. **Offline-first is the moat.** The POS must never block a sale due to connectivity.
2. **Payments are append-only.** Use `payment_events` as the source of truth. Never mutate a finalized payment.
3. **Security by default.** RLS, least-privilege roles, no secrets in source.
4. **AI is grounded in real data.** Every Ledmi insight must cite real sales/inventory numbers; no hallucinated claims.
5. **Simple beats clever.** Prefer explicit, readable code over clever abstractions.

---

## 10. Non-Goals (Repeated for Clarity)

- We are **not** a payment processor. We integrate Paystack only.
- We are **not** deploying to production Supabase without credentials. We produce deployable code and local scripts.
- We are **not** supporting every African country in MVP. Ghana only.
- We are **not** building full accounting/GL in MVP. Reporting only.

---

**Locked and ready. See `docs/MASTER_PLAN.md` for the phased execution plan.**
