# LedgerMind OS

An offline-first, AI-powered retail operating system for African retail chains.

## Repository layout

| Path | Purpose |
|---|---|
| `ledgermindv1-main/` | Next.js back-office dashboard |
| `flutter_billing_app-main/` | Flutter mobile POS |
| `flutter_ml_credit_card_data_extractor-main/` | ML credit-card scanner Flutter module |
| `infra/supabase/migrations/` | Ordered Supabase SQL migrations |
| `infra/supabase/seed/` | Seed scripts for roles and demo data |
| `supabase/functions/` | Deployable Supabase Edge Functions |
| `supabase/templates/` | LedgerMind-branded email templates |
| `docs/` | Architecture and design documentation |

## Key documents

- `LEDGERMIND_OS_GUIDE.md` — Comprehensive implementation guide (start here).
- `PRD.md` — Product requirements (locked).
- `AGENTS.md` — Team charter and engineering playbook.
- `GO_LIVE_CHECKLIST.md` — Real-time production setup and remaining tasks.
- `ledgermindv1-main/TASK_REPORT.md` — Latest task report.
- `ledgermindv1-main/README.md` — Dashboard local setup.

## Status

- Dashboard ↔ Supabase integration: working.
- POS backend RPCs and Edge Functions: deployed.
- Flutter POS login branch-selection bug: fixed.
- Remaining blockers: Supabase plan/custom SMTP for branded emails and Google OAuth credentials.

Start with <ref_file file="C:\Users\DELL\Desktop\POS\LEDGERMIND_OS_GUIDE.md" />.
