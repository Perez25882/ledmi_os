# LedgerMind OS — Go-Live Checklist

This checklist covers everything that must be done on the real Supabase project, payment provider accounts, and app stores before LedgerMind OS can be used by real businesses.

## Test account (delete before production)

- **Email:** `test@ledgermind.local`
- **Password:** `Test1234!`
- This account owns a seeded demo business (`Demo Business` / `Accra HQ`) with sample products and inventory.
- It is useful for demos and QA. Delete the auth user and its business row before going live.

---

## 1. Supabase project configuration

### 1.1 Auth provider: Google OAuth
The Next.js dashboard already calls `supabase.auth.signInWithOAuth({ provider: 'google' })`. Google OAuth is also enabled in `supabase/config.toml`, but it cannot be pushed to Supabase while the free-tier email-template block above is active, and it needs real Google credentials.

1. In [Google Cloud Console](https://console.cloud.google.com/), create OAuth 2.0 credentials for a Web application.
2. Add authorized redirect URI:
   ```
   https://xsdvanqkhricgmbabamu.supabase.co/auth/v1/callback
   ```
3. Copy **Client ID** and **Client Secret**.
4. In Supabase Dashboard → Authentication → Providers → Google:
   - Enable Google provider.
   - Paste Client ID and Client Secret.
   - Save.

Alternatively, after upgrading/adding SMTP, set `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` and `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET` environment variables and re-run `supabase config push`.

### 1.2 Auth emails: sender name and templates
⚠️ **Blocked by Supabase free tier.** `supabase config push` returned:
> "Email template modification is not available for free tier projects using the default email provider. Please upgrade your plan or configure a custom SMTP provider."

You must do this in Supabase Dashboard once you upgrade or add SMTP:
1. Supabase Dashboard → Authentication → Email Templates:
   - Set **Site URL** to your production domain (`https://yourdomain.com`). — *Do not push local `http://127.0.0.1:3000` to production; update `supabase/config.toml` `site_url` and re-push after upgrading/adding SMTP.*
   - Set **Sender email** to a domain you own, e.g. `support@ledgermind.com`.
   - Set **Sender name** to `LedgerMind`.
2. Replace the default Supabase-branded templates with LedgerMind-branded HTML.
   - The source templates are in `supabase/templates/` (invite, confirmation, recovery, magic_link).
   - Paste the HTML into the matching Supabase email template.
3. If you use a custom SMTP:
   - Supabase Dashboard → Authentication → SMTP.
   - Configure your provider (SendGrid, Mailgun, AWS SES, etc.).
   - Set sender name to `LedgerMind`.

### 1.3 Deploy Supabase Edge Functions
The POS relies on the `paystack-initiate` Edge Function to start Paystack transactions.

✅ **Done via CLI:**
- Linked project `xsdvanqkhricgmbabamu`.
- Set Edge Function secrets `PAYSTACK_SECRET_KEY` and `PAYSTACK_WEBHOOK_SECRET`.
- Deployed `paystack-initiate` and `paystack-webhook`.

Still required manually:
1. Configure the Paystack webhook URL in your Paystack Dashboard:
   ```
   https://xsdvanqkhricgmbabamu.supabase.co/functions/v1/paystack-webhook
   ```
2. Set Paystack callback URL for web/MoMo flows (if different from webhook):
   ```
   https://xsdvanqkhricgmbabamu.supabase.co/functions/v1/paystack-webhook
   ```

### 1.4 Environment variables for local / hosted dashboard
Create `ledgermindv1-main/.env` from `.env.example`:

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
NEXT_PUBLIC_APP_URL=https://yourdomain.com
```

### 1.5 Flutter POS environment
Create `flutter_billing_app-main/.env`:

```env
SUPABASE_URL=https://xsdvanqkhricgmbabamu.supabase.co
SUPABASE_ANON_KEY=<anon-key>
PAYSTACK_PUBLIC_KEY=pk_test_...
```

### 1.6 ML card scanner environment
Create `flutter_ml_credit_card_data_extractor-main/.env`:

```env
SUPABASE_URL=https://xsdvanqkhricgmbabamu.supabase.co
SUPABASE_ANON_KEY=<anon-key>
```

---

## 2. Payments and PCI compliance

### 2.1 Paystack account setup
1. Sign up / log in at [Paystack](https://paystack.com/).
2. Get your test keys (then live keys after approval).
3. Add the webhook URL above.
4. Enable the payment channels you want (card, mobile money).

### 2.2 Card data safety (MUST do before real customers)
The current ML scanner extracts the full card number and expiry. Before production you must ensure:
- The full PAN is **never stored** in app state, local storage, logs, or crash reports.
- The full PAN is **never sent** to your own backend.
- The scanner result should be passed directly to Paystack's PCI-compliant checkout (hosted page or SDK) and only the Paystack reference and last-4 digits should remain in the app.

The code change already made:
- `checkout_page.dart` no longer stores or displays the full card number; it only shows `•••• •••• •••• <last4>`.

Recommended next step:
- Replace the in-app card display with Paystack's hosted checkout (`transaction/initialize`) for card payments. The scanner can pre-fill nothing; it simply signals that a card payment is being attempted and the cashier opens the Paystack URL.
- For Ghana mobile money, Paystack `transaction/initialize` already returns a URL where the customer authorizes payment.

---

## 3. Dashboard and web app

### 3.1 Build and deploy
1. Run lint and build:
   ```powershell
   cd ledgermindv1-main
   npm run build
   ```
2. Deploy to Vercel, Netlify, or your host of choice.
3. Set environment variables in the hosting dashboard.
4. Ensure `/auth/callback` is reachable at your production URL.

### 3.2 Delete test data before public access
Run via SQL or a script:

```sql
-- Replace with the real test user UUID after looking it up
DELETE FROM auth.users WHERE email = 'test@ledgermind.local';
DELETE FROM businesses WHERE name = 'Demo Business';
```

Also clear any leftover onboarding-test users from earlier development.

---

## 4. Flutter POS (mobile)

### 4.1 Android build
1. Update `android/app/build.gradle` package name and version.
2. Add your Paystack public key and Supabase anon key in `android/app/src/main/AndroidManifest.xml` if needed.
3. Build release APK/AAB:
   ```powershell
   cd flutter_billing_app-main
   flutter build appbundle --release
   ```
4. Upload to Google Play Console (internal testing first).

### 4.2 Bluetooth printer
1. Test with real Bluetooth thermal printers (commonly used in Ghana).
2. Verify pairing, printing receipts, and reconnection after sleep.

### 4.3 Offline sync
1. Simulate intermittent network on a real device.
2. Confirm sales queue in Hive and sync to Supabase when online.
3. Verify inventory stays consistent after sync (idempotency keys prevent double deduction).

---

## 5. ML card scanner module

### 5.1 Integration with POS
1. The scanner app/module is a separate Flutter package.
2. It is invoked from `CheckoutPage` via the `/card-scanner` route.
3. Verify on-device that the camera preview works and card number/expiry are recognized in low light.

### 5.2 PCI review
Engage a PCI SAQ-A review (or Paystack's guidance) before capturing real cards with the camera.

---

## 6. Operations and support

### 6.1 Staff onboarding flow
1. Owner signs up on web.
2. Owner creates business + first branch.
3. Owner invites manager/cashier/accountant by email from `/dashboard/users`.
4. Cashier installs POS app, logs in, opens shift.
5. Cashier sells, accepts cash / MoMo / card.
6. Manager/owner views sales, inventory, and Ledmi insights on dashboard.

### 6.2 End-of-day
1. Cashier closes shift on POS (`close_shift` RPC).
2. Cashier reconciles actual cash vs expected cash.
3. Manager reviews shift report in dashboard.

### 6.3 Backups and monitoring
- Enable Supabase Point-in-Time Recovery (PITR) on paid plans.
- Set up Realtime for live sales if desired.
- Monitor Paystack webhook failures in Paystack Dashboard.
- Monitor Edge Function invocations in Supabase Logs.

---

## 7. Final verification commands

Run these before each release:

```powershell
# Dashboard
npm run build

# POS
flutter analyze
flutter build appbundle --release

# Scanner module
flutter analyze
```

---

## 8. Post-MVP roadmap (not in this checklist)

- Bulk product import (CSV).
- Multi-currency support.
- Advanced Ledmi analytics and demand forecasting.
- Native iOS POS build.
- Hardware barcode scanner integration.
