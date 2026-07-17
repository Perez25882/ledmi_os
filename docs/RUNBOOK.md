# LedgerMind OS — Pilot Runbook

**Purpose:** Step-by-step guide for deploying and running LedgerMind OS for the first 10 Accra retail chains.

---

## 1. Pre-flight checklist

- [ ] Supabase project created with Postgres 15+.
- [ ] Paystack business account in test/live mode.
- [ ] Flutter POS devices (Android 8+ or iOS 13+) with Bluetooth thermal printer and camera.
- [ ] Dashboard deployed to Vercel / self-hosted Node 22.
- [ ] Environment variables copied from `.env.example` and secrets set.

## 2. Supabase setup

### Option A — Migration runner script (recommended)

1. Add `DATABASE_URL` to `ledgermindv1-main/.env` (from Supabase Dashboard > Database > Connection string).
2. Run:
   ```bash
   cd scripts
   npm install
   npm run apply
   npm run verify
   ```

### Option B — Supabase CLI

1. Ensure Docker Desktop is running.
2. Run migrations in order:
   ```bash
   npx supabase db reset
   # or apply files 001 to 009 manually via SQL Editor
   ```
3. Seed default roles:
   ```sql
   SELECT * FROM seed_default_roles();
   ```
3. Verify Edge Functions deploy:
   ```bash
   supabase functions deploy paystack-webhook
   supabase functions deploy paystack-initiate
   ```
4. Set Edge Function secrets:
   - `PAYSTACK_SECRET_KEY`
   - `PAYSTACK_WEBHOOK_SECRET`
   - `SUPABASE_SERVICE_ROLE_KEY`
5. Configure Paystack webhook URL:
   ```
   https://<project>.supabase.co/functions/v1/paystack-webhook
   ```
6. Enable Realtime on `inventory` table for dashboard live stock updates.

## 3. Dashboard onboarding

1. Open `/auth/sign-up` and create the owner account.
2. After sign-in, go to `/dashboard/onboarding`.
3. Enter business name and first branch name.
4. Click **Create + Demo Data** to populate sample products and stock.
5. Invite cashiers/managers via `/api/invitations` or build a UI in `/dashboard/users`.

## 4. Flutter POS setup

1. Install the APK/IPA on the device.
2. Sign in with a cashier account.
3. Select the correct branch.
4. Open a shift from the home screen and record the opening float.
5. Pair the Bluetooth thermal printer in Settings.

## 5. Daily operations

### Cashier
- Open shift at start of day.
- Scan or search products, add to cart, choose payment method.
- For cash: enter amount tendered and confirm.
- For card/MoMo: choose Card/MoMo, scan card if desired, then open Paystack URL.
- After customer pays, the webhook finalizes the sale and prints the receipt.
- For returns: tap the refund icon, enter the sale ID, select items, and confirm.
- Close shift at end of day and enter actual cash in drawer.

### Manager
- Monitor `/dashboard/overview` for today's revenue and alerts.
- Use `/dashboard/inventory/supabase` to check live stock.
- Use `/dashboard/catalog` to add/edit products and categories.
- Review `/dashboard/refunds` and `/dashboard/shifts` for reconciliation.
- Ask Ledmi AI questions in `/dashboard/ai-insights/supabase`.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| POS cannot login | Wrong Supabase URL/anon key | Check `.env` and rebuild |
| Payment not finalizing | Webhook secret mismatch | Re-copy secret from Paystack dashboard |
| Sale fails offline | No network | Sale is queued; verify sync when online |
| Inventory not updating | Realtime not enabled | Enable Realtime on `inventory` |
| Push alerts not received | VAPID keys missing | Generate and add to dashboard env |

## 7. Support escalation

1. Check `activity_logs` in Supabase.
2. Review `webhook_receipts` for payment events.
3. Capture device logs and network requests from the POS.
4. File a ticket with the support team including sale/refund IDs.
