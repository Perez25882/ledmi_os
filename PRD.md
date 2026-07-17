# Product Requirements Document (PRD)

## LedgerMind OS — AI-Powered Retail Operating System for African Chains

**Version:** 1.0 — MVP  
**Date:** 2026-07-13  
**Author:** Chief Engineer / PM  
**Status:** Draft for team review  
**Related documents:** `RESEARCH.md`

---

## 1. Vision

LedgerMind OS is a unified retail operating system for African retail chains. It combines an **offline-first mobile POS**, a **web-based back-office dashboard**, and an **embedded AI assistant (Ledmi)** into a single platform built on a secure, multi-tenant backend.

Our goal is to give multi-store retailers the operational intelligence they need to sell more, waste less, and never run out of stock — while remaining affordable and reliable in low-connectivity environments.

> **One-liner:** The AI-powered retail OS that lets African chains sell offline, manage inventory online, and make smarter decisions automatically.

---

## 2. Problem Statement

Retail chains in Ghana and similar African markets face a consistent set of problems:

1. **Internet is unreliable.** A cloud-only POS stops working when connectivity drops, causing lost sales.
2. **Inventory is blind.** Owners cannot see stock levels, dead stock, or reorder needs across branches in real time.
3. **Decisions are reactive.** Most POS systems only show what happened yesterday; they do not predict what will happen tomorrow.
4. **Payment fragmentation.** Cashiers juggle cash, mobile money, cards, and bank transfers with no unified checkout flow.
5. **Existing solutions are either too simple (SellarPro) or too expensive (Oval POS at $120–150/outlet/mo).**

Our research confirms that no current competitor owns the full stack: offline mobile POS + predictive AI + multi-branch visibility + embedded payments + GRA compliance.

---

## 3. Target Market & Users

### Primary market
- **Ghana first**, then Nigeria and Kenya.
- Independent retail chains with **3 to 20 branches**.
- Verticals: supermarkets, pharmacies, electronics, fashion retail, beauty supply, wholesale/distribution.

### Secondary market
- Single-store businesses that want to scale into chains.
- Distributors and wholesalers with van/field sales teams.

### User personas

| Persona | Role | Primary need |
|---|---|---|
| **Ama, Owner** | Chain owner / CEO | Real-time P&L across branches, AI restocking advice, compliance |
| **Kofi, Branch Manager** | Store manager | Daily sales reconciliation, staff oversight, low-stock alerts |
| **Adjoa, Cashier** | Frontline cashier | Fast checkout, offline sales, easy refunds, receipt printing |
| **Daniel, Accountant** | Finance / auditor | GRA E-VAT reports, sales ledgers, audit trail |

---

## 4. Product Goals & Success Metrics

### Goals

1. **Sell anywhere:** Cashiers can complete a full checkout in under 10 seconds, even without internet.
2. **See everything:** Owners get a single dashboard showing sales, stock, and margins across all branches.
3. **Predict and prevent:** Ledmi surfaces at least 3 actionable insights per week per business (reorder, anomaly, margin).
4. **Stay compliant:** GRA E-VAT invoices are generated automatically in Ghana.
5. **Pay any way:** Unified checkout accepts cash, MTN MoMo, Vodafone Cash, AirtelTigo, and card (via Paystack).

### Success metrics (MVP, 6 months post-launch)

| Metric | Target |
|---|---|
| Pilot businesses | 10 Ghanaian chains |
| Average checkout time | < 10 seconds |
| Offline sale sync success rate | > 99.5% |
| Dashboard daily active users | 60% of registered managers/owners |
| AI insight click-through / action rate | > 25% |
| Monthly churn | < 5% |
| Uptime | > 99.9% |

---

## 5. MVP Scope Definition

### In scope for MVP

1. **Flutter POS app** (enhanced from existing `flutter_billing_app-main`)
   - Offline-first checkout
   - Barcode scanning (camera + Bluetooth scanner)
   - Cash, MoMo, card payments
   - Bluetooth thermal receipt printing
   - Basic shift/cashier management
   - Offline queue and automatic sync

2. **Supabase backend** (based on `database_architecture`)
   - Multi-tenant businesses, branches, users, roles
   - Products, inventory, categories, suppliers
   - Carts, sales, sale items, payments
   - Inventory logs and audit trail
   - GRA E-VAT invoice table
   - Paystack webhook endpoint

3. **LedgerMind Dashboard** (migrated from `ledgermindv1-main` to Supabase)
   - Login and business onboarding
   - Inventory management
   - Sales reports
   - Multi-branch overview
   - User/role management
   - GRA E-VAT report export

4. **Ledmi AI Assistant**
   - Conversational assistant embedded in dashboard and POS
   - Business summary and Q&A over sales/inventory
   - Low-stock, anomaly, and trend insights
   - Predictive reorder suggestions

5. **Card scanner integration**
   - ML credit-card scanner from `flutter_ml_credit_card_data_extractor-main` embedded as a checkout step
   - Card details sent directly to Paystack for tokenization; never stored locally or on our servers

### Out of scope for MVP

- Full accounting/GL module (reporting only; integrate with QuickBooks/Sage later).
- E-commerce storefront (post-MVP; keep schema ready).
- Supplier portal and purchase order workflow (post-MVP; basic reorder suggestions in scope).
- GRA E-VAT compliant invoice module (post-pilot; keep schema extensible).
- White-label / reseller program.
- Advanced manufacturing/BOM (post-MVP).

---

## 6. Non-Goals

- We are **not** building a payments processor. We integrate Paystack (primary), with Hubtel/Flutterwave as documented fallbacks only if needed.
- We are **not** storing full card numbers or CVV. PCI scope must remain minimal.
- We are **not** supporting every African country at launch. Ghana first.
- We are **not** replacing accountants. We give them better data and reports.

---

## 7. User Stories & Key Flows

### US-1: Cashier sells offline
> As a cashier, I want to scan products, accept cash, and print a receipt even when the internet is down, so that no sale is lost.

**Acceptance criteria:**
- POS detects offline state automatically.
- Cart, inventory deduction, and receipt are handled locally.
- Sale is queued and synced when connectivity returns.
- Duplicate sales are prevented via idempotency key.

### US-2: Owner sees cross-branch dashboard
> As an owner, I want to see today’s revenue, top products, and low-stock items across all my branches, so I can make decisions without visiting every store.

**Acceptance criteria:**
- Dashboard loads within 3 seconds for up to 20 branches.
- Data reflects synced sales and stock movements.
- Drill-down by branch, product, cashier, and date range.

### US-3: Ledmi predicts a stockout
> As a manager, I want the system to warn me 3 days before a product runs out and suggest a reorder quantity, so I avoid stockouts.

**Acceptance criteria:**
- Ledmi generates a reorder alert with confidence score.
- Alert includes current stock, sales velocity, suggested reorder quantity, and supplier.
- User can mark alert as actioned or dismiss it.

### US-4: Customer pays by card
> As a cashier, I want to scan a customer’s card with the camera to pre-fill card details, so checkout is faster and fewer manual errors occur.

**Acceptance criteria:**
- Card number and expiry are extracted via on-device ML Kit OCR.
- Data is sent directly to Paystack over TLS for tokenization.
- Our backend only receives the Paystack reference and last-4 digits.

### US-5: Standard receipt / invoice record
> As an accountant, I want every sale to generate an immutable receipt/invoice record, so the books are auditable.

**Acceptance criteria:**
- Each sale creates an immutable invoice record.
- Receipts show business details, items, totals, payment method, and timestamp.
- Exportable sales ledger for accounting use.
- GRA E-VAT compliant format with levies/QR code is a post-pilot enhancement.

### US-6: Refund / return
> As a cashier, I want to process a return and update inventory, so the books stay accurate.

**Acceptance criteria:**
- Return linked to original sale where possible.
- Inventory is restocked and sale total adjusted.
- Refund method recorded (cash, MoMo reversal, etc.).

---

## 8. Functional Requirements

### 8.1 Mobile POS (Flutter)

| ID | Requirement | Priority |
|---|---|---|
| POS-1 | Product search by name, barcode, SKU | P0 |
| POS-2 | Add/remove items, quantity edit, line discounts | P0 |
| POS-3 | Split payments across cash + MoMo + card | P1 |
| POS-4 | Accept MoMo (MTN/Vodafone/AirtelTigo) via Paystack | P0 |
| POS-5 | Card scanning via ML Kit + Paystack tokenization | P1 |
| POS-6 | Bluetooth thermal receipt printing (58mm/80mm) | P0 |
| POS-7 | Offline sale capture with local queue | P0 |
| POS-8 | Automatic background sync when online | P0 |
| POS-9 | Cashier login, shift open/close, end-of-day report | P0 |
| POS-10 | Refunds and returns | P1 |
| POS-11 | Hold/recall cart | P2 |

### 8.2 Back-Office Dashboard (Next.js)

| ID | Requirement | Priority |
|---|---|---|
| DASH-1 | Business onboarding, branch creation, user invitations | P0 |
| DASH-2 | Product catalog with categories, variants, barcodes, suppliers | P0 |
| DASH-3 | Inventory view with branch-level stock, low-stock alerts | P0 |
| DASH-4 | Sales ledger with filters and drill-down | P0 |
| DASH-5 | Multi-branch dashboard: revenue, margins, top products | P0 |
| DASH-6 | User roles and permissions (owner, manager, cashier, accountant) | P0 |
| DASH-7 | Invoice / receipt ledger export (CSV/PDF); GRA E-VAT format post-pilot | P1 |
| DASH-8 | Ledmi chat panel in dashboard | P1 |

### 8.3 AI Assistant (Ledmi)

| ID | Requirement | Priority |
|---|---|---|
| AI-1 | Natural-language Q&A over sales/inventory data | P1 |
| AI-2 | Proactive low-stock alerts with suggested reorder quantity | P1 |
| AI-3 | Sales anomaly detection (spikes/drops vs. prior period) | P1 |
| AI-4 | Top/bottom product performance summary | P1 |
| AI-5 | Margin analysis and pricing recommendations | P2 |
| AI-6 | Seasonal demand forecast | P2 |
| AI-7 | Tool calling: add product, update stock quantity | P2 |

---

## 9. Technical Architecture

### 9.1 High-level diagram

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         LedgerMind OS                               │
├─────────────────┬─────────────────────┬─────────────────────────────┤
│  Flutter POS    │  LedgerMind Web     │  Paystack / Hubtel / MoMo   │
│  (offline +     │  Dashboard          │  Payment Providers          │
│   card scanner) │  (Next.js +         │                             │
│                 │   Supabase client)  │                             │
└────────┬────────┴──────────┬──────────┴──────────────┬──────────────┘
         │                   │                         │
         └───────────────────┴─────────────────────────┘
                             │
              ┌──────────────▼──────────────┐
              │      Supabase Platform        │
              │  Postgres + Auth + Realtime   │
              │  + Edge Functions (webhooks)  │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │   database_architecture       │
              │   (multi-tenant schema)       │
              └─────────────────────────────┘
```

### 9.2 Backend of record

- **Supabase Postgres** is the single source of truth.
- The existing `database_architecture` SQL files provide the starting schema.
- We will migrate LedgerMind from Firebase to Supabase.
- The Flutter POS will use `supabase_flutter` client and offline queue.

### 9.3 Sync strategy

- **Local cache:** Hive (already used in the Flutter app).
- **Conflict rule:** Server wins for product/pricing; client wins for local sales with server-side idempotency checks.
- **Sync frequency:** Immediate when online; every 60 seconds when idle; manual pull-to-sync.
- **Idempotency:** Every sale and inventory mutation carries a client-generated UUID.

### 9.4 AI pipeline

- **Data source:** Supabase Postgres queries.
- **Compute:** Server-side API route in LedgerMind dashboard (Next.js) or Supabase Edge Function.
- **Model:** Moonshot/Kimi (`moonshot-v1-8k`) as already prototyped in `ledgermindv1-main/lib/ai-service.ts`.
- **Context window:** Summarized business snapshot (inventory, 30–90 days of sales) injected into system prompt.
- **Tool calling:** Function definitions for `add_inventory_item` and `update_stock_quantity`.

---

## 10. Data Model (MVP)

Based on `database_architecture`, with MVP simplifications:

### Core entities

| Entity | Purpose |
|---|---|
| `businesses` | Multi-tenant root; one business = one chain |
| `branches` | Physical store locations |
| `users` / `auth.users` | Cashiers, managers, owners, accountants |
| `user_business_roles` | RBAC mapping |
| `custom_roles` | Role definitions and permission JSONB |
| `categories` | Product categories per business |
| `products` | Catalog: name, barcode, SKU, price, variants, supplier |
| `inventory` | Branch-level stock quantity |
| `inventory_logs` | Immutable audit of stock changes |
| `carts` | In-progress POS sessions per cashier/branch |
| `cart_items` | Items in a cart |
| `sales` | Finalized sales transactions |
| `sale_items` | Line items per sale |
| `payments` | Payment records per sale |
| `invoices` | GRA E-VAT invoices |
| `ai_insights` | Generated insights from Ledmi |
| `payment_intents` / `payment_events` | Event-sourced card/MoMo payment state |

### MVP schema changes from existing SQL

1. Add `branches` table if not present.
2. Link `carts`, `sales`, `inventory` to `branch_id`.
3. Add `gr_e_vat_invoice_number` and QR fields to `invoices`.
4. Keep `payment_events` immutable append-only ledger.

---

## 11. UI/UX Requirements

### Mobile POS
- **Speed first:** One-tap product add, large touch targets, minimal navigation.
- **Offline indicator:** Clear icon when offline; sync status visible.
- **Receipt preview:** Show total, payment method, change due, and QR code.
- **Dark mode support** for shops with bright displays.

### Dashboard
- **Mobile responsive:** Owners often check from phones.
- **Role-based views:** Cashiers see POS only; accountants see reports; owners see everything.
- **Ledmi floating button:** Persistent chat assistant in bottom-right.
- **Branch selector:** Global dropdown to switch context.

---

## 12. Security & Compliance

### Authentication
- Supabase Auth with email/password and magic link.
- JWT contains `business_id` and role claims.
- Session cookies in dashboard; token refresh in mobile app.

### Authorization
- Row Level Security (RLS) on every table.
- Helper functions: `user_belongs_to_business()`, `user_has_permission()`, `user_is_owner()`.
- Cashiers cannot delete products or view other businesses’ data.

### Payments & PCI
- **Full PAN/CVV never stored** in our database or device logs.
- Card scanner sends card data directly to Paystack from the Flutter app.
- Our backend records only: payment method, reference, last-4 digits, status.
- Paystack webhooks verified via HMAC-SHA512 in Supabase Edge Function.

### GRA E-VAT (Ghana) — Deferred
- **MVP decision:** GRA E-VAT invoice module is not required for pilot launch.
- The `invoices` table will still be immutable and receipt-ready, but without GRA-specific levies/QR codes.
- Tax/levy fields will be kept configurable so GRA compliance can be added as a fast follow-up after pilot.

### Data privacy
- Encrypt sensitive fields at rest.
- Audit logs for all inventory mutations and permission changes.
- GDPR-aligned deletion policy for account closure (soft-delete + data retention rules).

---

## 13. Integrations

| Service | Integration point | Priority |
|---|---|---|
| **Paystack** | Card tokenization, MoMo, webhooks — primary and only payment provider for MVP | P0 |
| **Hubtel** | Backup MoMo aggregation if Paystack MoMo has issues | P2 |
| **Flutterwave** | Backup card/MoMo processor | P2 |
| **MNotify / Twilio** | SMS receipts and alerts | P2 |
| **WhatsApp Business API** | Digital receipts and notifications | P2 |
| **QuickBooks / Sage** | Accounting export | Post-MVP |
| **WooCommerce / Shopify** | E-commerce sync | Post-MVP |

---

## 14. AI/ML Requirements

### Data preparation
- Clean, timestamped sales and inventory events.
- Automatic daily aggregation: revenue, units sold, stock levels, margins.
- Feature store: sales velocity per SKU per branch, stockout history, price elasticity proxies.

### Model behaviors
1. **Reorder recommendation:**
   - Input: current stock, sales velocity (units/day), supplier lead time, safety stock.
   - Output: days until stockout, suggested reorder quantity, confidence score.
2. **Anomaly detection:**
   - Input: daily/weekly sales per SKU per branch.
   - Output: spikes/drops outside 2 standard deviations with explanation.
3. **Margin advisor:**
   - Input: cost price, selling price, sales volume.
   - Output: products with declining margins and suggested price band.

### Proactive generation
- **Scheduled daily:** Every morning Ledmi generates a "daily brief" for each branch/owner.
- **Real-time triggers:** After a sync batch completes, Ledmi re-evaluates stockouts and anomalies and pushes alerts if thresholds are crossed.
- **In-app prompts:** Dashboard shows actionable cards; POS shows only critical stock alerts to avoid cashier distraction.

### Output handling
- Insights are saved to `ai_insights` table.
- Shown in dashboard feed and as push notifications.
- Cashiers can ask Ledmi voice/text questions in POS.

---

## 15. Offline-First Strategy

### What works offline
- Browsing product catalog (last-synced copy in Hive).
- Adding items to cart and applying discounts.
- Cash payments and receipt printing.
- End-of-shift reconciliation (queued).

### What requires connectivity
- MoMo/card payments that need provider confirmation.
- Multi-branch inventory transfers.
- User/role management.
- AI insight generation (can be queued).

### Sync rules
- Sales sync first, then inventory logs, then analytics aggregation.
- On conflict, preserve both records and flag for manual review if totals diverge.
- Sync progress visible in POS and dashboard.

---

## 16. Release Plan / Roadmap

### Phase 1 — Foundation (Weeks 1–3)
- Finalize Supabase schema and deploy `database_architecture` MVP subset.
- Build Paystack webhook Edge Function with HMAC verification.
- Set up auth, business onboarding, and branch creation.

### Phase 2 — Core POS Online (Weeks 4–7)
- Add Supabase client to Flutter billing app.
- Implement product sync, online checkout, receipt printing.
- Build cashier login and shift management.

### Phase 3 — Offline Sync & Card Scanning (Weeks 8–11)
- Implement Hive offline queue and background sync.
- Embed ML credit-card scanner and Paystack tokenization.
- Add refunds and returns.

### Phase 4 — Dashboard MVP (Weeks 12–15)
- Migrate LedgerMind to Supabase.
- Build inventory, sales ledger, multi-branch dashboard, user management.
- Add GRA E-VAT invoice export.

### Phase 5 — Ledmi AI (Weeks 16–19)
- Wire up Kimi/Moonshot assistant.
- Implement reorder, anomaly, and margin insights.
- Add proactive notifications.

### Phase 6 — Pilot & Hardening (Weeks 20–24)
- Onboard 10 Ghanaian chain pilot customers.
- Fix sync edge cases, performance, and security.
- Prepare for public launch.

---

## 17. Pricing & Packaging (MVP Hypothesis)

| Plan | Target | Price (Ghana) | Includes |
|---|---|---|---|
| **Starter** | Single shop | **Free** | 1 branch, 1 user, basic POS, inventory, dashboard |
| **Growth** | 3–10 branches | **GHS 150 / branch / mo** | Unlimited users, AI insights, multi-branch, offline sync |
| **Scale** | 10+ branches | **GHS 120 / branch / mo** | All features + dedicated support, API access, custom onboarding |

- Annual billing: 2 months free.
- Card/MoMo transaction fees pass through at cost; no markup.
- Hardware (Bluetooth printer, scanner) sold separately or via partner.

---

## 18. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Offline sync conflicts | High | Idempotency keys, server-side reconciliation, manual review queue |
| Paystack integration delays | High | Build provider-agnostic payment abstraction; keep Hubtel as a documented fallback path |
| AI insights feel generic | Medium | Always ground responses in real data; show confidence scores; allow feedback |
| LedgerMind Firebase migration is larger than expected | High | Run migration in parallel; keep Firebase read-only until cutover is validated |
| Data quality is poor | Medium | Enforce validation in POS; block malformed sales from syncing |
| Regulatory changes in Ghana | Medium | Design tax/levies as configurable; keep GRA module isolated |

---

## 19. Open Questions — Answered

| # | Question | Decision |
|---|---|---|
| 1 | Android only or Android + iOS in MVP? | **Both Android and iOS.** Core Android POS is built first; iOS follows immediately using the same Flutter codebase. |
| 2 | Primary payment provider? | **Paystack only** for MVP. Hubtel remains a documented fallback path if issues arise. |
| 3 | Ledmi on-demand or scheduled? | **Proactive + scheduled.** Daily morning brief plus real-time alerts after sync. |
| 4 | Hardware bundle at launch? | **No bundled hardware at MVP launch.** Provide a recommended hardware list and partner referrals; bundle program can be added after pilot feedback. |
| 5 | GRA E-VAT at launch? | **Deferred.** Keep schema extensible; add GRA module after pilot. |
| 6 | Pilot geography? | **Accra only** for the first 10 pilot chains. |

---

## 20. Conclusion

LedgerMind OS has a clear opportunity to win against Oval POS and other African competitors by delivering a **unified, offline-first, AI-powered retail operating system** at a price point that undercuts premium incumbents while offering deeper intelligence than budget players.

The MVP should prove the core loop:

> **Offline sale → payment → inventory update → dashboard → AI insight.**

If this loop works reliably for 10 Ghanaian chains, we have a platform worth scaling across Africa.

---

**Next step:** Open questions are answered and PRD is ready for implementation. Begin Phase 1 — build the Supabase backend foundation (schema + auth + Paystack webhook Edge Function).
