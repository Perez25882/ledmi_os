# LedgerMind OS — Comprehensive Implementation Guide

This is the single source of truth for what has been built, what has been verified, what remains before production, and how to run and deploy the system.

---

## 1. Executive summary

LedgerMind OS is an offline-first, AI-powered retail operating system for African retail chains. The current codebase integrates three applications around a shared Supabase backend:

- **Next.js dashboard** — back-office for owners, managers, cashiers, and accountants.
- **Flutter POS** — mobile point-of-sale for cashiers, with offline support.
- **Flutter ML card scanner** — credit-card scanner module used by the POS.

The MVP loop is:

> Offline sale → Paystack payment → inventory update → LedgerMind dashboard → Ledmi AI insight.

All major integration points are now wired and verified at the code/backend level. The remaining work is mostly environment configuration, payment-provider setup, and app-store release.

---

## 2. Architecture

### 2.1 Repository layout

```text
C:\Users\DELL\Desktop\POS
├── AGENTS.md                              # Team charter & engineering rules
├── PRD.md                                 # Locked product requirements
├── RESEARCH.md                            # Competitive research
├── LEDGERMIND_OS_GUIDE.md                 # This file
├── GO_LIVE_CHECKLIST.md                   # Production setup checklist
├── README.md                              # Root index
├── ledgermindv1-main/                     # Next.js dashboard
│   ├── README.md
│   ├── TASK_REPORT.md
│   ├── app/                               # Next.js App Router pages
│   ├── components/
│   ├── lib/supabase/                      # Supabase clients, data helpers, permissions
│   └── package.json
├── flutter_billing_app-main/              # Flutter POS
│   ├── lib/features/
│   │   ├── auth/                          # Login, branch selection
│   │   ├── billing/                       # Cart, checkout, payment
│   │   ├── product/                       # Catalog sync
│   │   ├── settings/                      # Printers, devices
│   │   └── sync/                          # Offline queue
│   └── pubspec.yaml
├── flutter_ml_credit_card_data_extractor-main/  # ML scanner module
├── infra/supabase/migrations/             # Ordered SQL migrations (001–011)
├── infra/supabase/seed/                   # Default roles seed
├── supabase/
│   ├── config.toml                        # Supabase CLI config (auth, email, OAuth)
│   ├── functions/                         # Deployable Edge Functions
│   │   ├── paystack-initiate/
│   │   └── paystack-webhook/
│   └── templates/                         # LedgerMind-branded email templates
└── docs/                                  # Architecture & design docs
    ├── DECISIONS.md
    ├── LEDMI_DESIGN.md
    ├── MASTER_PLAN.md
    ├── ONBOARDING_DESIGN.md
    ├── RUNBOOK.md
    ├── SECURITY.md
    ├── SYNC_PROTOCOL.md
    └── TRAINING.md
```

### 2.2 Tech stack

| Layer | Technology |
|---|---|
| Backend / Database | Supabase (Postgres 15+, Auth, Edge Functions, Realtime) |
| Dashboard | Next.js 16, React 18, TypeScript, Tailwind CSS, shadcn/ui |
| Mobile POS | Flutter 3.x, BLoC, Hive, go_router, supabase_flutter, mobile_scanner, print_bluetooth_thermal |
| AI | NVIDIA NIM via `/api/ledmi/*` server routes |
| Payments | Paystack (Edge Functions + webhook) |
| Offline sync | Hive local cache + idempotency keys + background sync |

### 2.3 Data model

Key tables:

- `businesses`, `branches`
- `custom_roles`, `user_business_roles`
- `categories`, `products`, `inventory`
- `inventory_logs`
- `sales`, `sale_items`, `refunds`, `refund_items`
- `shifts`
- `payment_intents`, `payment_events`, `webhook_receipts`
- `activity_logs`
- `push_subscriptions`

RLS policies are enabled on all tables. Access is controlled by auth helpers:

- `user_belongs_to_business(business_id)`
- `user_is_owner(business_id)`
- `user_has_permission(business_id, permission)`

---

## 3. What has been implemented

### 3.1 Dashboard (`ledgermindv1-main`)

- Supabase auth (email/password + Google OAuth UI wired).
- Onboarding flow: sign-up → create business + branch → seed demo data.
- Role-based sidebar navigation (owner, manager, cashier, accountant).
- Pages:
  - Overview (today's revenue, branch performance, stock alerts)
  - Inventory (Supabase-backed, low-stock badges)
  - Catalog (products and categories CRUD)
  - Sales ledger
  - Shifts
  - Users/team management (invite, change role, remove)
  - Reports (revenue trend, category distribution, summary)
  - Settings
  - AI insights / floating Ledmi chat
- Server-side data fetching with Supabase server client.
- Ledmi AI chat powered by `/api/ledmi/chat` and `/api/ledmi/insights`.
- Ledmi proactive insight card on the Overview page (summary + recommendation).
- Removed Firebase dependency entirely.
- Removed subscription/pricing/admin UI.

### 3.2 Supabase backend

- Migrations `001` through `011` applied to the hosted project.
- Auth helpers and RLS policies on all tables.
- RPC functions:
  - `process_checkout_cash`
  - `create_checkout_intent`
  - `process_payment_capture`
  - `process_refund`
  - `open_shift`
  - `close_shift`
- Edge Functions:
  - `paystack-initiate` — starts a Paystack transaction from a checkout intent.
  - `paystack-webhook` — receives and verifies Paystack webhooks, finalizes sales.
- Schema fixes:
  - Added `branch_id` to `activity_logs` and `inventory_logs`.
  - Fixed refund/shift audit-log inserts to use correct columns.
  - Fixed inventory log column names in refund flow.

### 3.3 Flutter POS

- Supabase auth login.
- Branch selection (fixed the `user_business_roles` → `branches` relationship bug).
- Product catalog sync from Supabase into Hive for offline use.
- Cart, discounts, cash tendered/change.
- Cash checkout via `process_checkout_cash` RPC.
- Card/MoMo checkout via Paystack `transaction/initialize` (Edge Function deployed).
- Offline queue for cash sales with background sync.
- Shift open/close with float and reconciliation.
- Bluetooth thermal printer integration scaffold.
- Card scanner integration; full PAN no longer stored/displayed (only last-4).

### 3.4 ML card scanner

- Flutter module that extracts card number and expiry via camera.
- Returns data to the POS checkout.
- PCI-safe: full PAN is not persisted in app state; only last-4 is shown.

### 3.5 Security hardening

- Removed `listUsers()` data leak from dashboard users page.
- Removed subscription metadata from signup.
- Added `.gitignore` rules for `.env` files in Flutter and Edge Function folders.
- No Firebase admin SDK bypass remains.
- All deleted legacy Firebase API routes and dead components.

---

## 4. What has been verified

| Test | Result |
|---|---|
| Next.js `npm run build` | ✅ Passes |
| Flutter POS `flutter analyze` | ✅ No issues |
| Flutter scanner `flutter analyze` | ✅ No issues |
| Dashboard auth → onboarding → overview | ✅ Works end-to-end |
| Dashboard pages load (owner role) | ✅ All protected pages return 200 |
| Ledmi proactive insights | ✅ Parses correctly and displays on overview |
| Ledmi chat | ✅ Answers questions grounded in real data |
| Seed demo API | ✅ Idempotent; creates business/branch/products/inventory |
| Backend cash sale RPC | ✅ Creates sale and decrements inventory |
| Dashboard reflects sale | ✅ `/dashboard/sales` loads with sale data |
| POS branch selection query | ✅ Fixed and re-analyzed |
| Edge Function deployment | ✅ `paystack-initiate` and `paystack-webhook` deployed |
| Edge Function secrets | ✅ `PAYSTACK_SECRET_KEY` and `PAYSTACK_WEBHOOK_SECRET` set |

### Test account

Use this account for local demos and QA. Delete before production.

- **Email:** `test@ledgermind.local`
- **Password:** `Test1234!`
- **Business:** `Demo Business`
- **Branch:** `Accra HQ`
- **Products:** Bottled Water 500ml, Soda Can 330ml, Potato Chips 50g
- **Inventory:** 100 units each

---

## 5. Current blockers

These cannot be completed without external credentials or a Supabase plan change:

### 5.1 Supabase free-tier email-template restriction
- `supabase config push` failed with:
  > "Email template modification is not available for free tier projects using the default email provider. Please upgrade your plan or configure a custom SMTP provider."
- Because of this, LedgerMind-branded sender name/email templates and the Google OAuth config push cannot be applied remotely.

### 5.2 Google OAuth credentials
- The UI and `supabase/config.toml` are wired, but real Client ID / Client Secret from Google Cloud Console are required.

### 5.3 Paystack webhook URL
- The `paystack-webhook` Edge Function is deployed, but the webhook URL must be added in your Paystack Dashboard.

### 5.4 PCI-safe card payments
- The scanner no longer stores the full PAN, but before real customers use it you should switch card payments to Paystack's hosted checkout page so the full PAN never touches app state at all.

### 5.5 Flutter release build
- Release APK/AAB build and Google Play Console submission require an Android keystore and Play Console access.

### 5.6 Node.js version warning
- Environment is Node 20. Supabase packages warn that Node 22+ will be required in the future. Dev and build still work.

---

## 6. Next steps

### Immediate (do these first)

1. **Configure Paystack webhook**
   - URL: `https://xsdvanqkhricgmbabamu.supabase.co/functions/v1/paystack-webhook`
   - Add it in Paystack Dashboard → Settings → Webhooks.

2. **Enable Google OAuth**
   - Create OAuth 2.0 credentials in Google Cloud Console.
   - Authorized redirect URI: `https://xsdvanqkhricgmbabamu.supabase.co/auth/v1/callback`
   - Paste Client ID / Secret in Supabase Dashboard → Authentication → Providers → Google.

3. **Brand emails**
   - Upgrade Supabase plan or add custom SMTP.
   - In Supabase Dashboard, set sender name to `LedgerMind` and upload templates from `supabase/templates/`.

### Short-term

4. **End-to-end payment test**
   - Log into the Flutter POS with the test account.
   - Open a shift.
   - Create a cash sale and verify it appears in the dashboard.
   - Create a Paystack (MoMo/card) test sale and verify webhook finalizes it.

5. **Real-device testing**
   - Install POS debug APK on an Android device.
   - Test Bluetooth printer pairing.
   - Test offline sale queue and sync.

6. **PCI review**
   - Replace in-app card display with Paystack hosted checkout.
   - Confirm no full PAN/CVV in logs, state, or storage.

### Long-term

7. **Release**
   - Generate signed Android App Bundle.
   - Create Google Play listing and internal testing track.
   - Deploy dashboard to Vercel/Netlify with production env vars.

8. **Operations**
   - Enable Supabase PITR backups.
   - Set up monitoring and alerting.
   - Train staff using the demo account.

---

## 7. Local development setup

### 7.1 Dashboard

```powershell
cd ledgermindv1-main
cp .env.example .env
# Edit .env with your Supabase/Paystack/NVIDIA keys
npm install
npm run dev
```

Open `http://localhost:3000`.

### 7.2 Flutter POS

```powershell
cd flutter_billing_app-main
cp .env.example .env
# Edit .env with Supabase URL/anon key and Paystack public key
C:\tools\flutter\bin\flutter.bat pub get
C:\tools\flutter\bin\flutter.bat run -d chrome --web-port 8080
```

For a real Android device:

```powershell
C:\tools\flutter\bin\flutter.bat run -d <device-id>
```

### 7.3 ML card scanner

```powershell
cd flutter_ml_credit_card_data_extractor-main
C:\tools\flutter\bin\flutter.bat pub get
C:\tools\flutter\bin\flutter.bat run -d chrome --web-port 8081
```

### 7.4 Supabase CLI

If you need to re-apply migrations or deploy functions:

```powershell
cd C:\Users\DELL\Desktop\POS
supabase link --project-ref xsdvanqkhricgmbabamu
supabase functions deploy paystack-initiate --project-ref xsdvanqkhricgmbabamu
supabase functions deploy paystack-webhook --project-ref xsdvanqkhricgmbabamu
```

---

## 8. Environment variables

### Dashboard (`ledgermindv1-main/.env`)

```env
NEXT_PUBLIC_SUPABASE_URL=https://xsdvanqkhricgmbabamu.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
DATABASE_URL=<postgres-connection-string>
PAYSTACK_SECRET_KEY=sk_test_...
PAYSTACK_WEBHOOK_SECRET=whsec_...
NVIDIA_API_KEY=nvapi-...
NVIDIA_MODEL=meta/llama-3.1-8b-instruct
NEXT_PUBLIC_VAPID_PUBLIC_KEY=<vapid-public>
VAPID_PRIVATE_KEY=<vapid-private>
NEXT_PUBLIC_APP_NAME=LedgerMind OS
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### Flutter POS (`flutter_billing_app-main/.env`)

```env
SUPABASE_URL=https://xsdvanqkhricgmbabamu.supabase.co
SUPABASE_ANON_KEY=<anon-key>
PAYSTACK_PUBLIC_KEY=pk_test_...
```

### Edge Functions (set via CLI)

```powershell
supabase secrets set PAYSTACK_SECRET_KEY=sk_test_...
supabase secrets set PAYSTACK_WEBHOOK_SECRET=whsec_...
```

### Google OAuth (Supabase Dashboard or env vars)

```env
SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID=<google-client-id>
SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET=<google-client-secret>
```

---

## 9. Key files and references

- `AGENTS.md` — team charter and coding standards
- `PRD.md` — locked product requirements
- `GO_LIVE_CHECKLIST.md` — exact production commands
- `ledgermindv1-main/TASK_REPORT.md` — latest changes and blockers
- `docs/SECURITY.md` — security architecture
- `docs/SYNC_PROTOCOL.md` — offline sync design
- `docs/LEDMI_DESIGN.md` — AI assistant design

---

## 10. Important reminders before going live

1. Delete the test account `test@ledgermind.local` and the `Demo Business`.
2. Rotate any keys that were shared or committed (even temporarily).
3. Confirm `.env` files are in `.gitignore` and never committed.
4. Verify Paystack is in test mode until you are ready for real money.
5. Complete PCI review for card data handling.
6. Upgrade Node.js to 22+ when feasible.
7. Migrate `middleware.ts` to the Next.js 16 `proxy` convention if the deprecation warning becomes an error.
