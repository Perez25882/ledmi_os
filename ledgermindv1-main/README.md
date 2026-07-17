# LedgerMind OS — Dashboard

The LedgerMind OS back-office dashboard. Built with Next.js 16, React 18, TypeScript, Tailwind CSS, and shadcn/ui. It runs against a Supabase backend and works together with the Flutter POS and ML card scanner modules.

## Current state

- Supabase-only auth (email/password + Google OAuth ready).
- Business onboarding and demo seeding.
- Role-based access control: owner, manager, cashier, accountant.
- Catalog, inventory, sales ledger, shifts, users, reports, and the Ledmi AI assistant.
- No Firebase dependency.
- No subscription/pricing UI in the dashboard.

## Tech stack

- **Framework:** Next.js 16 (App Router)
- **Language:** TypeScript
- **Styling:** Tailwind CSS
- **UI components:** shadcn/ui + Radix UI
- **Backend:** Supabase (Postgres, Auth, Edge Functions, Realtime)
- **AI:** NVIDIA NIM via `/api/ledmi/*`
- **Payments:** Paystack via Supabase Edge Functions

## Local development

1. Install dependencies:
   ```powershell
   npm install
   ```

2. Copy environment variables:
   ```powershell
   cp .env.example .env
   ```

3. Fill in `.env` with your Supabase and Paystack credentials.

4. Run the dev server:
   ```powershell
   npm run dev
   ```

5. Open `http://localhost:3000`.

## Test account

A demo account is seeded for manual testing:

- **Email:** `test@ledgermind.local`
- **Password:** `Test1234!`

Delete this account and its business data before going live.

## Build

```powershell
npm run build
```

## Important notes

- Email sender name/templates and Google OAuth require a Supabase plan upgrade or custom SMTP. See `../GO_LIVE_CHECKLIST.md`.
- Paystack Edge Functions (`paystack-initiate`, `paystack-webhook`) must be deployed from `../supabase/functions/`.
- See `TASK_REPORT.md` for the latest changes and blockers.
- Start with the comprehensive guide: `../LEDGERMIND_OS_GUIDE.md`.
