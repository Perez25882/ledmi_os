# Secure Retail OS Security Architecture

This document explains the security mechanisms enforcing system integrity, PCI compliance, and multi-tenant isolation.

## Paystack Webhook Best Practice (Crucial)

Since the Flutter POS Card Scanner extracts sensitive data but never stores it locally, it directly dispatches the payment charge securely to Paystack via a tokenized session. However, the client (Flutter) CANNOT be trusted to confirm payment success.

**The Golden Rule:** The frontend MUST NOT directly call the `process_card_sale` RPC function.

### Recommended Secure Architecture

1. **Supabase Edge Function (Webhook Receiver):**
   Create a dedicated Edge Function in Supabase (`/functions/paystack-webhook`). Paystack will post success events to this securely hosted endpoint.
   
2. **Signature Verification (Mandatory):**
   The Edge Function MUST verify the `x-paystack-signature` header using `HMAC-SHA512` and your secret `PAYSTACK_SECRET_KEY` stored securely in Supabase Vault / Edge Secrets. If the signature doesn't match, drop the request immediately (returns 401).

3. **Verifying Payload Data:**
   Extract the `amount`, `status`, and metadata (`cart_id`) from the verified webhook body.

4. **Service-Role Execution:**
   Inside the Edge Function, initialize the Supabase client using the `SERVICE_ROLE_KEY`. This elevates privileges strictly for this verified internal operation.
   Call the `process_card_sale` RPC via the service-role client.

**Why this is the best practice:**
- Guaranteed authenticity: Only Paystack can generate the correct HMAC signature.
- Prevents Replay/Spoofing attacks: Malicious actors cannot pretend they paid by curling your DB directly.
- The `SERVICE_ROLE_KEY` is only available server-side, protecting the database from public arbitrary execution.

## 1. Multi-Tenant Isolation
All tables include a `business_id`. The Row Level Security (RLS) policies enforce a strict `Deny by Default` methodology. 
A user authenticates via `auth.uid()`, but the system utilizes the `user_business_roles` table (via the `SECURITY DEFINER` function `user_belongs_to_business()`) to inherently scope all queries. A cashier for Business A cannot even list products for Business B, solving Insecure Direct Object References (IDOR).

## 2. Granular Role-Based Access Control (RBAC)
Instead of hardcoded roles, a flexible `custom_roles` table allows business owners to define roles using a JSONB `permissions` structure (e.g., `{"process_sales": true, "manage_inventory": false}`). The RLS policies evaluate `user_has_permission()`. This prevents privilege escalation.

## 3. Atomic Operations & Race Conditions
Inventory is the most critical asset. If a checkout is processed, the system MUST prevent "double selling" or "overselling" when two POS terminals scan the last item simultaneously.
- `SELECT ... FOR UPDATE` row locks are acquired for the exact inventory items being purchased. 
- A table-level constraint `CHECK (quantity >= 0)` ensures mathematical impossibility of negative stock.
- This creates an atomic PostgreSQL transaction. If ANY constraint fails (e.g., inventory drops below 0), the entire cart, payment, and invoice generation strictly ROLLBACK.

## 4. PCI Compliance via Data Exclusion
The `payments` table guarantees compliance by mathematically excluding PCI Scope fields. There are no columns for PAN (Full Number), CVV, or Expiration. Even if the database was entirely compromised, no usable credit card data could be leaked, because it exists solely as `card_last4` and `provider_reference` for receipt printing.

## 5. Immutable Audit Trails
Inventory adjustments (via `inventory_logs`) and application actions (via `activity_logs`) are append-only. No application role (except perhaps a super admin) has DELETE rights on logs. This satisfies enterprise auditing requirements.
