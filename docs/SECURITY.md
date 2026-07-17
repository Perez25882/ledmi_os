# LedgerMind OS — Security & Compliance Playbook

**Status:** Living document for Phase 1  
**Owner:** Security & RLS Specialist + Lead  
**Related:** `PRD.md`, `AGENTS.md`

---

## 1. Threat Model

| Threat | Likelihood | Impact | Mitigation |
|---|---|---|---|
| One business reads another business’s data | Medium | High | RLS on every table, JWT `business_id` claim, helper functions |
| Cashier deletes/updates products or inventory | Medium | High | Permission-based policies, deny-by-default RLS |
| Payment webhook replay / spoofing | Medium | High | HMAC-SHA512 verification, webhook_receipts idempotency |
| Card PAN/CVV stored or logged | Low | Critical | Never store full card data; send directly to Paystack |
| Offline sync creates duplicate sales | Medium | Medium | Idempotency keys, server-side deduplication |
| Stolen service role key | Low | Critical | Store in Supabase secrets, never in client or repo |
| Brute-force login | Medium | Medium | Supabase Auth rate limiting, strong passwords |
| XSS / CSRF in dashboard | Medium | High | Input validation, CSP, SameSite cookies, server-side auth checks |

---

## 2. Authentication

- Use Supabase Auth for both Flutter and Next.js.
- JWT should carry `business_id` and role claims for RLS helpers.
- Magic links for owners/managers; email/password for cashiers.
- Implement session refresh in Flutter.
- Force logout on password reset or role revocation.

## 3. Authorization (RLS)

- Every table must have `ENABLE ROW LEVEL SECURITY`.
- Default policy: deny all. Then explicitly allow.
- Use helper functions:
  - `user_belongs_to_business(p_business_id UUID)`
  - `user_is_owner(p_business_id UUID)`
  - `user_has_permission(p_business_id UUID, p_permission TEXT)`
- Cashiers can only see/modify their own carts and sales.
- Managers/owners see all branch data within their business.
- Payment event tables are append-only for normal users; write via service role/Edge Function.

## 4. Payments & PCI

- **Never store full PAN or CVV** in Postgres, Hive, logs, or crash reports.
- Flutter card scanner sends card data directly to Paystack.
- Backend records only: Paystack reference, last-4 digits, brand, status, amount.
- Paystack webhooks are verified with HMAC-SHA512 using `PAYSTACK_WEBHOOK_SECRET`.
- Webhook handler is idempotent; duplicate events do not double-finalize sales.
- Maintain an immutable `webhook_receipts` audit log.

## 5. Data Privacy

- Encrypt sensitive fields at rest where Supabase provides transparent encryption.
- Do not log PII (emails, phone numbers) in production logs.
- Provide account deletion workflow that soft-deletes and schedules data purge.
- Comply with Ghana Data Protection Act and GDPR where applicable.

## 6. API & Sync Security

- All Flutter → Supabase calls use the anon key + RLS.
- Server-side dashboard calls use service role only when necessary.
- Validate idempotency keys and timestamp windows to prevent replay attacks.
- Use HTTPS/TLS for all network traffic.

## 7. Secrets Management

| Secret | Stored In |
|---|---|
| `SUPABASE_ANON_KEY` | Flutter .env, Next.js public env |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard secrets, Next.js server env only |
| `PAYSTACK_PUBLIC_KEY` | Flutter .env, Next.js public env |
| `PAYSTACK_SECRET_KEY` | Supabase Edge Function secrets, Next.js server env |
| `PAYSTACK_WEBHOOK_SECRET` | Supabase Edge Function secrets |
| `NVIDIA_API_KEY` | Next.js server env only |

- `.env` files must not be committed.
- `.env.example` files are committed as templates.

## 8. Audit & Logging

- `inventory_logs` records every stock change.
- `activity_logs` records important user actions.
- `payment_events` records every payment state change.
- Dashboard should provide an audit view for owners.

## 9. Pre-Pilot Security Checklist

- [ ] All tables have RLS enabled.
- [ ] No SELECT/INSERT/UPDATE policies allow cross-business access.
- [ ] Paystack webhook HMAC verification is implemented and tested.
- [ ] Card PAN/CVV are not stored or logged anywhere.
- [ ] Service role key is not in client code or GitHub.
- [ ] Dashboard has secure session middleware.
- [ ] Flutter offline queue encrypts or protects queued sale data.
- [ ] Input validation on all RPC endpoints and forms.
- [ ] Dependency audit (no known critical vulnerabilities).

---

**This document must be updated as new features and threats are discovered.**
