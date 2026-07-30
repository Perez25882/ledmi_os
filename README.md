# LedgerMind OS

An offline-first, AI-powered retail operating system for African retail chains.

## Repository layout

| Path | Purpose |
|---|---|
| `ledgermindv1-main/` | Next.js back-office dashboard |
| `flutter_billing_app-main/` | Flutter mobile POS (card scanner is folded in — see AD-20) |
| `infra/supabase/migrations/` | Ordered Supabase SQL migrations |
| `infra/supabase/seed/` | Seed scripts for roles and demo data |
| `infra/supabase/functions/` | Edge Function **sources** (edit these) |
| `supabase/functions/` | Edge Function **deploy copies** — kept byte-identical to the sources above; `node scripts/verify-edge-functions.js` enforces it |
| `supabase/templates/` | LedgerMind-branded email templates |
| `supabase/config.toml` | Supabase CLI project root (migrations, auth, function JWT settings) |
| `scripts/` | Migration runner and pre-deploy verification scripts |
| `docs/` | Architecture and design documentation |

## Key documents

- `LEDGERMIND_OS_GUIDE.md` — Comprehensive implementation guide (start here).
- `PRD.md` — Product requirements (locked).
- `AGENTS.md` — Team charter and engineering playbook.
- `GO_LIVE_CHECKLIST.md` — Real-time production setup and remaining tasks.
- `ledgermindv1-main/TASK_REPORT.md` — Latest task report.
- `ledgermindv1-main/README.md` — Dashboard local setup.

## Status

Verified 2026-07-30:

| Check | Command | Result |
|---|---|---|
| Dashboard typecheck | `npm run typecheck` | clean |
| Dashboard lint | `npm run lint` | 0 errors, 47 warnings |
| Dashboard build | `npm run build` | passes |
| POS static analysis | `flutter analyze` | 0 issues |
| POS unit tests | `flutter test` | 20 passing |
| Edge Function sync | `node scripts/verify-edge-functions.js` | in sync |

- Dashboard ↔ Supabase integration: working.
- Flutter POS login branch-selection bug: fixed.

**Blockers before real customers:**

1. **Re-deploy both Edge Functions.** The deployed webhook was rejecting every
   Paystack callback (missing `verify_jwt = false`), and the deployed
   `paystack-initiate` had no mobile-money support. Both are fixed in the repo but
   not yet pushed — see `GO_LIVE_CHECKLIST.md` §1.3.
2. **Android release signing.** Generate the upload keystore and `key.properties`;
   confirm the `com.ledgermind.pos` application ID before the first Play upload,
   since it is permanent — see §4.1.
3. Supabase paid plan or custom SMTP for branded auth emails, and Google OAuth
   credentials — see §1.1 and §1.2.
4. Delete the seeded test account and demo business — see §3.2.

Start with <ref_file file="C:\Users\DELL\Desktop\POS\LEDGERMIND_OS_GUIDE.md" />.
