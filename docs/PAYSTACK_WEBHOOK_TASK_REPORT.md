# Payment Engineer Task Report — Paystack Webhook Edge Function

## Summary

Built the Supabase Edge Function for LedgerMind OS that receives Paystack webhooks for `charge.success`, `charge.failed`, `refund.success`, etc.

What was delivered:

- `index.ts` — HMAC-SHA512 signature verification, raw webhook persistence in `webhook_receipts`, canonical `payment_events` insertion, and sale finalization via `safe_finalize_sale(payment_intent_id)`.
- `deno.jsonc` — Deno import map and test task.
- `test.ts` — Deno tests that generate a Paystack-compatible HMAC signature and exercise the handler with a mocked Supabase client.
- `../../migrations/005_paystack_webhook_rpc.sql` — `safe_finalize_sale` and `process_payment_capture` RPCs made idempotent and transactional.

Key decisions:

- `safe_finalize_sale` attaches the capture marker inside the same transaction as inventory decrement and sale creation, so a failure rolls back cleanly and duplicate webhooks cannot double-finalize.
- Paystack webhook events are mapped to the canonical `payment_events` event types allowed by the schema (`payment_captured`, `payment_failed`, `payment_refunded`, `payment_partially_refunded`, `chargeback_created`, `chargeback_won`, `chargeback_lost`, `webhook_received`).
- Full PAN/CVV are never stored or logged; only Paystack reference and last-4/card brand flow through the legacy tables.
- Duplicate webhooks are handled by:
  - `webhook_receipts` unique constraint on `(provider, provider_event_id, event_type)`.
  - `payment_events` partial unique index on `(provider, provider_event_id)`.
  - `safe_finalize_sale` raising on a non-active cart, which the handler treats as a no-op.

## Files Changed

```text
C:\Users\DELL\Desktop\POS\infra\supabase\functions\paystack-webhook\
├── index.ts
├── deno.jsonc
├── test.ts
└── TASK_REPORT.md

C:\Users\DELL\Desktop\POS\infra\supabase\migrations\005_paystack_webhook_rpc.sql
```

## How to Test

### 1. Run the Deno unit tests

Requires [Deno](https://deno.land/) installed locally.

```bash
cd "C:\Users\DELL\Desktop\POS\infra\supabase\functions\paystack-webhook"
deno task test
# or explicitly:
deno test --allow-net --allow-env test.ts
```

### 2. Deploy the function locally with Supabase CLI

```bash
cd "C:\Users\DELL\Desktop\POS\infra\supabase"
supabase functions serve paystack-webhook --env-file .env
```

Required environment variables:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
PAYSTACK_WEBHOOK_SECRET=whsec_...
PAYSTACK_SECRET_KEY=sk_test_...
```

### 3. Trigger a test webhook

From another terminal (or using a tool like `curl`/Postman):

```bash
BODY='{"event":"charge.success","data":{"id":123456,"reference":"LM-ORDER-001","amount":50000,"paid_at":"2026-07-13T12:00:00Z"}}'
SIG=$(echo -n "$BODY" | openssl dgst -sha512 -hmac "whsec_..." | sed 's/^.* //')
curl -X POST http://localhost:54321/functions/v1/paystack-webhook \
  -H "x-paystack-signature: $SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY"
```

On Windows PowerShell you can compute the signature with:

```powershell
$secret = "whsec_..."
$body = '{"event":"charge.success","data":{"id":123456,"reference":"LM-ORDER-001","amount":50000,"paid_at":"2026-07-13T12:00:00Z"}}'
$hmac = New-Object System.Security.Cryptography.HMACSHA512
$hmac.Key = [Text.Encoding]::UTF8.GetBytes($secret)
$sig = ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($body)) | ForEach-Object { $_.ToString("x2") }) -join ''
Invoke-RestMethod -Uri http://localhost:54321/functions/v1/paystack-webhook -Method Post -Headers @{"x-paystack-signature"=$sig;"Content-Type"="application/json"} -Body $body
```

### 4. Verify the database

After a successful `charge.success` webhook:

- A row exists in `webhook_receipts` with `signature_valid = true`.
- A `payment_captured` row exists in `payment_events` for the matched `payment_intent`.
- `payment_processing_markers` has a row for the intent.
- `sales`, `sale_items`, `invoices`, and `inventory_logs` reflect the finalized sale.

## Blockers / Notes for the Lead

1. **Deno runtime not installed locally.** The unit tests were written but could not be executed in this environment. The lead should run `deno task test` after ensuring Deno is on the CI/agent path.
2. **Migrations 001–004 must be applied first.** `005_paystack_webhook_rpc.sql` depends on the core schema (`payment_intents`, `payment_events`, `payment_processing_markers`, `webhook_receipts`, `inventory`, `carts`, etc.). The Backend Architect (`agent_01`) owns those migrations.
3. **MoMo vs card method in legacy `payments` table.** `safe_finalize_sale` records the legacy payment with `method = 'CARD'`. Paystack Ghana handles both cards and mobile money under the same `charge.success` event. Once the schema adds a `method` or `channel` column to `payment_intents`, this RPC should use that value instead of hardcoding `CARD`.
4. **No production Supabase credentials are present.** This deliverable is deployable code only; actual deployment requires project credentials and the `PAYSTACK_WEBHOOK_SECRET` from the Paystack dashboard.

## Suggested Next Task

Backend Architect (`agent_01`) should confirm the 001–004 schema migrations include the event-sourced tables exactly as defined in `database_architecture/01_schema.sql`, and Security/RLS (`agent_03`) should add RLS policies for `webhook_receipts` and `payment_events` (insert-only for service role, read-only for business users).
