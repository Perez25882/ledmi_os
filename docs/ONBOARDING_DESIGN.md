# LedgerMind OS — Onboarding & JWT Claims Design

**Status:** Design for Phase 1 closure / Phase 2 prerequisite  
**Owner:** Lead Engineer  
**Related:** `PRD.md`, `AGENTS.md`, `docs/SYNC_PROTOCOL.md`, `infra/supabase/migrations/003_auth_helpers.sql`

---

## 1. Problem

The RLS helper `current_business_id()` reads `business_id` from the JWT claim, but nothing currently sets that claim when a user signs up or is assigned to a business. The Flutter app also needs to know which business and branch the cashier belongs to after login.

## 2. Decisions

### 2.1 Do not rely on a custom JWT `business_id` claim for MVP

Most RLS policies already use `user_belongs_to_business(business_id)`, which checks the `user_business_roles` table for `auth.uid()`. This is more flexible and works for users who belong to multiple businesses.

The only policy that currently uses `current_business_id()` is `webhook_receipts_select_finance`. This is acceptable for MVP because webhook receipts are an internal audit table; business-level isolation can be tightened later by adding a `business_id` column to `webhook_receipts`.

### 2.2 Flutter POS discovers business/branch at runtime

After login, the Flutter app will:
1. Query `user_business_roles` for the current user to find assigned businesses.
2. If the user has one business and one branch, select it automatically.
3. If the user has multiple branches, show the branch selection screen.
4. Persist the selected `business_id` and `branch_id` in `SessionManager` (Hive).

This avoids the need for custom JWT claims and matches the current implementation in `branch_selection_page.dart`.

### 2.3 Dashboard onboarding is service-role only

A new business is created by an authenticated owner/manager through the dashboard. The dashboard server uses the service-role Supabase client to:
1. Insert a row into `businesses`.
2. Insert one or more rows into `branches`.
3. Insert an owner role into `custom_roles` (or reuse the default seeded role).
4. Insert the current user's `user_business_roles` mapping with the owner role.

Because this requires the service-role key, it must run server-side (Next.js Server Action or API route), never in the browser.

## 3. Recommended Implementation

### 3.1 Dashboard onboarding API route

Create `app/api/onboarding/create-business/route.ts`:
- Method: `POST`
- Body: `{ businessName: string, branchName: string }`
- Uses `createServiceClient()` from `lib/supabase/server.ts`
- Gets current user from `createServerClientForUser()`
- Creates business, branch, and `user_business_roles` owner mapping
- Returns `{ businessId, branchId }`

### 3.2 Flutter POS runtime discovery

Update `branch_selection_page.dart` to also query `user_business_roles` so it can group branches by business and handle multi-business users.

### 3.3 Optional: webhook_receipts business scoping (post-pilot)

Add `business_id UUID` to `webhook_receipts`, populate it from the matched `payment_intent`, and replace the `current_business_id()` RLS policy with `user_belongs_to_business(business_id)`.

## 4. Demo / Test Data

For Phase 2 local testing without a full onboarding UI, run `infra/supabase/seed/002_demo_business.sql` after manually creating an auth user. The script creates a demo business and branch, then maps the first auth user as owner.
