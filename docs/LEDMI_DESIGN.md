# Ledmi Proactive Insight Pipeline — Design Document

**Status:** Design ready for Phase 5 implementation  
**Owner:** AI / Analytics Lead (`agent_07`)  
**Related docs:** `PRD.md` §8.3, §14; `AGENTS.md`; `docs/MASTER_PLAN.md`; `database_architecture/01_schema.sql`; `ledgermindv1-main/lib/ai-service.ts`

---

## 1. Goals & Principles

1. **Grounded in real data.** Every Ledmi insight must cite real sales, inventory, or margin numbers. No invented figures.
2. **Actionable first.** Each insight should answer: what changed, why it matters, and what the user should do next.
3. **Cheap to run.** Heavy aggregations happen in Postgres/materialized views or Supabase cron jobs; LLM calls are reserved for summarisation and natural-language answers.
4. **Multi-tenant safe.** All queries are scoped to `business_id` and `branch_id` with RLS enforced.
5. **Pluggable model.** The pipeline is model-agnostic at the SQL/feature layer; NVIDIA NIM (`meta/llama-3.1-8b-instruct`) is the LLM used for chat and brief generation. The provider is configurable via env (`LEDMI_LLM_PROVIDER`); NVIDIA NIM is the default for MVP.

---

## 2. Data Preparation

### 2.1 Assumed schema additions

The current `database_architecture/01_schema.sql` is branch-agnostic. `002_branch_model.sql` adds:

```sql
CREATE TABLE IF NOT EXISTS branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    location VARCHAR(255),
    phone VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(business_id, name)
);

-- Add branch_id to inventory, carts, sales, invoices, inventory_logs
-- All branch_id columns are NOT NULL after 002, so every operational row is explicitly branch-scoped.
ALTER TABLE inventory ADD COLUMN IF NOT EXISTS branch_id UUID;
ALTER TABLE inventory ALTER COLUMN branch_id SET NOT NULL;
ALTER TABLE inventory ADD CONSTRAINT fk_inventory_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;
ALTER TABLE inventory ADD CONSTRAINT pk_inventory PRIMARY KEY (product_id, branch_id);

ALTER TABLE carts ADD COLUMN IF NOT EXISTS branch_id UUID;
ALTER TABLE carts ALTER COLUMN branch_id SET NOT NULL;
ALTER TABLE carts ADD CONSTRAINT fk_carts_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

ALTER TABLE sales ADD COLUMN IF NOT EXISTS branch_id UUID;
ALTER TABLE sales ALTER COLUMN branch_id SET NOT NULL;
ALTER TABLE sales ADD CONSTRAINT fk_sales_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

ALTER TABLE invoices ADD COLUMN IF NOT EXISTS branch_id UUID;
ALTER TABLE invoices ALTER COLUMN branch_id SET NOT NULL;
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;

ALTER TABLE inventory_logs ADD COLUMN IF NOT EXISTS branch_id UUID;
ALTER TABLE inventory_logs ALTER COLUMN branch_id SET NOT NULL;
ALTER TABLE inventory_logs ADD CONSTRAINT fk_inventory_logs_branch
    FOREIGN KEY (branch_id) REFERENCES branches(id) ON DELETE CASCADE;
```

### 2.2 Required SQL views/functions

#### `daily_sales_by_branch` materialized view

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_sales AS
SELECT
    s.business_id,
    s.branch_id,
    DATE(s.created_at) AS sale_date,
    p.id AS product_id,
    p.name AS product_name,
    p.supplier_id,
    SUM(si.quantity) AS units_sold,
    SUM(si.subtotal) AS revenue,
    SUM((si.unit_price - p.cost_price) * si.quantity) AS gross_margin,
    COUNT(DISTINCT s.id) AS transaction_count
FROM sales s
JOIN sale_items si ON si.sale_id = s.id
JOIN products p ON p.id = si.product_id
WHERE s.created_at >= NOW() - INTERVAL '90 days'
GROUP BY s.business_id, s.branch_id, DATE(s.created_at), p.id, p.name, p.supplier_id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_sales_pk
ON mv_daily_sales (business_id, branch_id, sale_date, product_id);
CREATE INDEX IF NOT EXISTS idx_mv_daily_sales_lookup
ON mv_daily_sales (business_id, branch_id, sale_date);
```

Refresh daily at 06:00 GMT (cron or pg_cron). For real-time insights after a sync batch, refresh concurrent:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
```

#### `inventory_snapshot` view

```sql
CREATE OR REPLACE VIEW v_inventory_snapshot AS
SELECT
    i.business_id,
    i.branch_id,
    i.product_id,
    p.name AS product_name,
    p.sku,
    p.barcode,
    p.selling_price,
    p.cost_price,
    p.supplier_id,
    p.reorder_threshold,
    i.quantity AS current_stock,
    (p.selling_price - p.cost_price) AS unit_margin,
    (p.selling_price - p.cost_price) * i.quantity AS stock_value_margin
FROM inventory i
JOIN products p ON p.id = i.product_id
WHERE p.deleted_at IS NULL;
```

#### `stock_velocity_per_sku_branch` materialized view (feature store)

This is the core feature store for Ledmi. It computes rolling sales velocity per SKU per branch.

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_stock_velocity AS
WITH sales_window AS (
    SELECT
        business_id,
        branch_id,
        product_id,
        sale_date,
        units_sold
    FROM mv_daily_sales
    WHERE sale_date >= CURRENT_DATE - INTERVAL '30 days'
),
velocity AS (
    SELECT
        business_id,
        branch_id,
        product_id,
        SUM(units_sold) AS total_units_30d,
        AVG(units_sold) AS avg_daily_units,
        STDDEV(units_sold) AS stddev_daily_units,
        COUNT(DISTINCT sale_date) AS days_with_sales,
        MAX(sale_date) AS last_sale_date
    FROM sales_window
    GROUP BY business_id, branch_id, product_id
)
SELECT
    v.business_id,
    v.branch_id,
    v.product_id,
    p.name AS product_name,
    p.supplier_id,
    p.reorder_threshold,
    s.quantity AS current_stock,
    v.total_units_30d,
    ROUND(v.avg_daily_units::numeric, 3) AS avg_daily_units,
    ROUND(COALESCE(v.stddev_daily_units, 0)::numeric, 3) AS stddev_daily_units,
    v.days_with_sales,
    CASE
        WHEN v.avg_daily_units > 0 THEN ROUND((s.quantity / v.avg_daily_units)::numeric, 1)
        ELSE NULL
    END AS days_until_stockout,
    CASE
        WHEN v.avg_daily_units > 0 THEN
            ROUND((
                (v.avg_daily_units * 14)                     -- 14 days demand
                + (1.65 * COALESCE(v.stddev_daily_units, 0))   -- safety stock (90% service level)
                - s.quantity
            )::numeric, 0)
        ELSE 0
    END AS suggested_reorder_qty,
    v.last_sale_date,
    NOW() AS computed_at
FROM velocity v
JOIN products p ON p.id = v.product_id
JOIN inventory s ON s.product_id = v.product_id AND s.branch_id = v.branch_id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_stock_velocity_pk
ON mv_stock_velocity (business_id, branch_id, product_id);
CREATE INDEX IF NOT EXISTS idx_mv_stock_velocity_stockout
ON mv_stock_velocity (business_id, days_until_stockout)
WHERE days_until_stockout IS NOT NULL AND days_until_stockout <= 7;
```

### 2.3 Feature store table / materialized view schema

For MVP we use materialized views as the feature store (simpler than a separate feature-store table). If later we need feature versioning, migrate to:

```sql
CREATE TABLE IF NOT EXISTS feature_store (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    feature_name VARCHAR(100) NOT NULL,   -- e.g. 'avg_daily_units_30d'
    feature_value NUMERIC NOT NULL,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(business_id, branch_id, product_id, feature_name)
);
CREATE INDEX IF NOT EXISTS idx_feature_store_lookup ON feature_store(business_id, branch_id, product_id, feature_name);
```

---

## 3. Insight Types

### 3.1 Reorder Recommendation

**Purpose:** Predict stockouts and suggest reorder quantities.

**Inputs:**

- `current_stock` from `inventory`
- `avg_daily_units` and `stddev_daily_units` from `mv_stock_velocity`
- `reorder_threshold` from `products`
- Optional: supplier lead time (defaults to 7 days until supplier table has `lead_time_days`)

**Formula:**

```text
days_until_stockout = current_stock / avg_daily_units
suggested_reorder_qty = (avg_daily_units * 14) + (1.65 * stddev_daily_units) - current_stock
safety_stock = 1.65 * stddev_daily_units  -- 90% service level
```

- Use a 14-day forward horizon (tunable per business).
- If `avg_daily_units = 0`, do not generate a reorder insight (no velocity).
- Round suggested quantity up to the nearest integer.

**Output shape:**

```json
{
  "insight_type": "reorder",
  "title": "Nido milk powder (1kg) will stock out in 2 days",
  "description": "Current stock: 8 units. Selling ~3.2 units/day at North Legon. Suggested reorder: 42 units.",
  "confidence_score": 0.89,
  "priority": "high",
  "data": {
    "product_id": "uuid",
    "branch_id": "uuid",
    "current_stock": 8,
    "avg_daily_units": 3.2,
    "days_until_stockout": 2.5,
    "suggested_reorder_qty": 42,
    "reorder_threshold": 10,
    "supplier_id": "uuid",
    "supplier_name": "Kantamanto Distributors"
  }
}
```

**Confidence score:**

- `1.0 - (stddev_daily_units / (avg_daily_units + 0.001))` clamped to `[0.55, 0.99]`.
- Lower if fewer than 7 days with sales in the last 30 days.

**Generation rule:**

- Generate when `days_until_stockout <= 7` OR `current_stock <= reorder_threshold`.
- Cap at 10 reorder insights per branch per run to avoid noise.

### 3.2 Anomaly Detection

**Purpose:** Detect unusual spikes or drops in sales, inventory movements, or margins.

**Statistical method:**

Z-score over daily sales per branch and per SKU:

```text
z = (today_value - rolling_mean_14d) / rolling_stddev_14d
```

**Thresholds:**

| Severity | Condition |
|---|---|
| High | `|z| >= 3.0` |
| Medium | `2.0 <= |z| < 3.0` |
| Low | `1.5 <= |z| < 2.0` (only surfaced if repeated 2+ days) |

**Output shape:**

```json
{
  "insight_type": "anomaly",
  "title": "Sales spike at East Legon",
  "description": "Revenue on 2026-07-12 was GHS 4,200 — 3.1x the 14-day average. Top driver: Indomie Instant Noodles (150g).",
  "confidence_score": 0.92,
  "priority": "medium",
  "data": {
    "branch_id": "uuid",
    "anomaly_date": "2026-07-12",
    "metric": "daily_revenue",
    "actual_value": 4200.00,
    "expected_value": 1354.83,
    "z_score": 3.12,
    "severity": "high",
    "top_products": [
      { "product_id": "uuid", "name": "Indomie Instant Noodles (150g)", "contribution": 890.00 }
    ]
  }
}
```

**Anomaly subtypes:**

1. **Sales spike/drop** (`metric: daily_revenue` or `daily_units`).
2. **Stock anomaly** (`metric: negative_stock` or `large_stock_adjustment`) from `inventory_logs`.
3. **Margin anomaly** (`metric: avg_unit_margin`) if selling price drops below cost price or margin compresses vs. prior period.

### 3.3 Margin Advisor

**Purpose:** Identify products or categories with declining margins and suggest price bands.

**Inputs:**

- `cost_price`, `selling_price` from `products`
- Units sold and revenue from `mv_daily_sales`

**Formula:**

```text
unit_margin = selling_price - cost_price
margin_rate = unit_margin / selling_price
category_avg_margin = AVG(margin_rate) per category
current_trend = margin_rate today vs 14-day average
```

**Output shape:**

```json
{
  "insight_type": "margin",
  "title": "Beverage margin compressed 4.2% this week",
  "description": "Average beverage margin fell from 28% to 23.8%. Coca-Cola 1.5L is now selling at a 2% loss on 12 units.",
  "confidence_score": 0.84,
  "priority": "medium",
  "data": {
    "category_id": "uuid",
    "category_name": "Beverages",
    "previous_margin_rate": 0.28,
    "current_margin_rate": 0.238,
    "affected_products": [
      {
        "product_id": "uuid",
        "name": "Coca-Cola 1.5L",
        "cost_price": 7.50,
        "selling_price": 7.35,
        "suggested_price_band": { "min": 9.00, "max": 10.50 }
      }
    ]
  }
}
```

**Suggested price band:**

```text
min_price = cost_price * 1.20        -- 20% minimum markup
max_price = cost_price * 1.50          -- 50% markup (category dependent)
```

**Generation rule:**

- Generate when `margin_rate < 0.15` for any product, or category margin drops >3 percentage points vs. prior 14-day average, and at least 5 units were sold.

---

## 4. Generation Cadence

### 4.1 Daily morning brief

- **Schedule:** 06:30 GMT every day via Supabase cron (`pg_cron`) or external scheduler calling an Edge Function.
- **Target:** One brief per business, optionally duplicated per branch for managers.
- **Content:**
  1. Yesterday's revenue vs. prior 7-day average.
  2. Top 3 and bottom 3 products by revenue.
  3. Reorder recommendations (stockout within 7 days).
  4. Any anomalies from the last 24 hours.
  5. Margin alert summary.

SQL to identify businesses to process:

```sql
SELECT DISTINCT business_id
FROM sales
WHERE created_at >= NOW() - INTERVAL '7 days';
```

### 4.2 Real-time triggers after a sync batch

When the Flutter POS uploads an offline batch:

1. Sync service inserts sales into `sales` / `sale_items`.
2. A Supabase database trigger or queue worker (Edge Function) calls `ledmi_evaluate_critical_alerts(business_id, branch_id)`.
3. Function only checks:
   - New stockouts (`current_stock = 0` after the batch).
   - New reorder thresholds crossed (`days_until_stockout <= 3`).
   - Large sales anomaly (`z_score >= 2.5` for the day).

Trigger pseudo-code:

```sql
CREATE OR REPLACE FUNCTION trg_after_sync_batch()
RETURNS TRIGGER AS $$
BEGIN
    -- schedule async Edge Function call or insert into job queue
    INSERT INTO ai_insight_jobs (business_id, branch_id, job_type, status, created_at)
    VALUES (NEW.business_id, NEW.branch_id, 'critical_alert', 'pending', NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### 4.3 Conditions for push notifications vs. in-app cards

| Insight type | Push notification | In-app card |
|---|---|---|
| Reorder with `days_until_stockout <= 2` | Yes | Yes |
| Reorder with `days_until_stockout 3–7` | No | Yes |
| Anomaly severity `high` | Yes | Yes |
| Anomaly severity `medium` / `low` | No | Yes |
| Margin advisor | No | Yes |
| Daily morning brief | Yes (owner/manager only) | Yes |
| Cashier POS critical stockout | Yes (in POS toast) | No |

Push notifications are implemented via a future service (MNotify/Twilio/WhatsApp) or Supabase Realtime event to the dashboard. For MVP, push is an out-of-scope integration; the pipeline must emit a `push_eligible` boolean so the notification layer can consume it later.

---

## 5. AI Assistant

### 5.1 API route / Edge Function design

**Recommended:** Supabase Edge Function `ledmi-assistant` exposed at `POST /functions/v1/ledmi-assistant`.

Reasons:
- Keeps AI API key server-side and out of the Next.js client bundle.
- Reusable from Flutter POS and dashboard.
- Can call Supabase RPC with `service_role_key` for grounded data.

**Fallback route (existing dashboard pattern):** `POST /api/ai/ask` in Next.js.

#### Request/response contract

```http
POST /functions/v1/ledmi-assistant
Content-Type: application/json
Authorization: Bearer <user-jwt>

{
  "business_id": "uuid",
  "branch_id": "uuid | null",
  "query": "What should I reorder today?",
  "conversation_history": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

Response:

```json
{
  "answer": "You should reorder Nido 1kg (42 units) and Indomie 150g (80 packs) for North Legon. Both stock out within 3 days.",
  "tool_calls": [],
  "data_refresh": false,
  "grounded_in": ["mv_stock_velocity", "v_inventory_snapshot"]
}
```

#### Edge Function flow

1. Verify JWT and `business_id` claim.
2. Load cached business snapshot (see §7).
3. Call NVIDIA NIM with system prompt + snapshot + user query + tools.
4. If tool calls, execute them via Supabase RPC (e.g. `upsert_inventory_item`, `adjust_stock`).
5. Return final text answer.

### 5.2 System prompt

```text
You are Ledmi, the AI inventory and sales assistant inside LedgerMind OS, a retail operating system used by multi-store chains in Ghana.

CURRENT BUSINESS CONTEXT:
- Business: {business_name}
- Branch: {branch_name}
- Snapshot date: {snapshot_computed_at}

BUSINESS SNAPSHOT (grounded data):
{snapshot_text}

RULES:
1. Base every claim on the snapshot above. If data is missing, say so.
2. GHS is the currency. Use it in all monetary answers.
3. Be concise. Use bullet points for lists.
4. When asked for predictions, explain that they are estimates derived from recent sales velocity.
5. Do not make up supplier names, product IDs, or stock numbers.
6. If the user asks about non-business topics, politely redirect to inventory, sales, margins, or operations.
7. Before calling a tool, confirm any missing required fields with the user.

TODAY'S DATE: {date}
```

`snapshot_text` is generated by a helper that renders the top-K low-stock items, recent revenue, top products, and anomalies. See §7 for snapshot format and caching.

### 5.3 Function/tool definitions

Tools use the OpenAI-compatible function-calling schema. Two tools are required for MVP:

#### `add_inventory_item`

```json
{
  "type": "function",
  "function": {
    "name": "add_inventory_item",
    "description": "Add a new product to the catalog and create an initial inventory record at the given branch. Only use when the user explicitly asks to add a new product.",
    "parameters": {
      "type": "object",
      "properties": {
        "name": { "type": "string", "description": "Product name" },
        "sku": { "type": "string", "description": "Stock keeping unit (optional)" },
        "barcode": { "type": "string", "description": "Barcode (optional)" },
        "category_id": { "type": "string", "description": "UUID of existing category (optional)" },
        "category_name": { "type": "string", "description": "Category name; will be created if not found" },
        "supplier_id": { "type": "string", "description": "UUID of existing supplier (optional)" },
        "selling_price": { "type": "number", "description": "Selling price in GHS" },
        "cost_price": { "type": "number", "description": "Cost price in GHS" },
        "initial_stock": { "type": "number", "description": "Initial quantity at branch" },
        "reorder_threshold": { "type": "number", "description": "Low-stock threshold (default 10)" }
      },
      "required": ["name", "selling_price", "cost_price", "initial_stock"]
    }
  }
}
```

Implementation should call a Postgres RPC such as `ledmi_add_inventory_item(...)` that inserts into `products`, `inventory`, and `inventory_logs` atomically.

#### `update_stock_quantity`

```json
{
  "type": "function",
  "function": {
    "name": "update_stock_quantity",
    "description": "Adjust the stock quantity of an existing product at a branch. Positive values add stock; negative values remove it.",
    "parameters": {
      "type": "object",
      "properties": {
        "product_id": { "type": "string", "description": "UUID of the product" },
        "branch_id": { "type": "string", "description": "UUID of the branch" },
        "quantity_change": { "type": "number", "description": "Amount to add (positive) or remove (negative)" },
        "reason": { "type": "string", "description": "Reason for the adjustment, e.g. 'stock count correction'" }
      },
      "required": ["product_id", "branch_id", "quantity_change"]
    }
  }
}
```

Implementation should call `ledmi_update_stock_quantity(...)` which:
1. Reads current `inventory.quantity`.
2. Computes `new_quantity`.
3. Inserts an `inventory_log` row with `reason = 'AI assistant: {reason}'`.
4. Updates `inventory.quantity`.

Both RPCs must enforce `business_id` scoping and RLS.

### 5.4 NVIDIA NIM API integration details

**Endpoint:** `https://integrate.api.nvidia.com/v1/chat/completions`

**Model:** `meta/llama-3.1-8b-instruct` (configurable via `NVIDIA_MODEL`)

**Headers:**

```http
Authorization: Bearer {NVIDIA_API_KEY}
Content-Type: application/json
```

**Request body:**

```json
{
  "model": "meta/llama-3.1-8b-instruct",
  "messages": [
    { "role": "system", "content": "<system prompt>" },
    { "role": "user", "content": "<query>" }
  ],
  "tools": [ "add_inventory_item", "update_stock_quantity" ],
  "temperature": 0.3,
  "max_tokens": 1500
}
```

**Token budget:**

- System prompt snapshot: ~2,000–3,000 tokens (capped at top 50 products, top 10 low-stock, 30-day summary).
- User query + history: ~500 tokens.
- Response: max 1,200 tokens.
- Total per request: comfortably within 8K context.

**Response parsing:**

```ts
const message = response.choices[0].message;
if (message.tool_calls && message.tool_calls.length > 0) {
  return { toolCalls: message.tool_calls, assistantMessage: message };
}
return { answer: message.content?.trim() };
```

**Cost control:**
- Use `temperature: 0.3` for deterministic operational answers.
- Limit conversation history to the last 10 messages.
- Cache the business snapshot for 10 minutes; do not rebuild it on every request.

---

## 6. Output & Feedback

### 6.1 `ai_insights` table schema

```sql
CREATE TYPE ai_insight_type AS ENUM ('reorder', 'anomaly', 'margin', 'brief', 'trend');
CREATE TYPE ai_insight_status AS ENUM ('pending', 'actioned', 'dismissed', 'snoozed');

CREATE TABLE IF NOT EXISTS ai_insights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    insight_type ai_insight_type NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    confidence_score DECIMAL(3, 2) CHECK (confidence_score >= 0 AND confidence_score <= 1),
    priority VARCHAR(20) NOT NULL DEFAULT 'medium',   -- low, medium, high, critical
    status ai_insight_status NOT NULL DEFAULT 'pending',
    is_read BOOLEAN NOT NULL DEFAULT false,
    push_eligible BOOLEAN NOT NULL DEFAULT false,
    push_sent BOOLEAN NOT NULL DEFAULT false,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,           -- structured payload from §3
    generated_by VARCHAR(50) NOT NULL DEFAULT 'sql',   -- sql, llm, cron, sync_trigger
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actioned_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_insights_business ON ai_insights(business_id, status, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_insights_branch ON ai_insights(branch_id, status, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_insights_type ON ai_insights(insight_type, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_insights_push ON ai_insights(push_eligible, push_sent) WHERE push_eligible = true AND push_sent = false;
CREATE INDEX IF NOT EXISTS idx_ai_insights_data ON ai_insights USING GIN(data jsonb_path_ops);
```

### 6.2 Confidence score and user feedback

**Confidence score meaning:**

- `0.90–1.00`: High certainty (rich history, low variance).
- `0.70–0.89`: Moderate certainty (some variance or sparse data).
- `0.50–0.69`: Low certainty; flag to user that data is limited.
- Do not generate insights below 0.50.

**Feedback states:**

| Status | Meaning |
|---|---|
| `pending` | New, not yet seen or acted upon |
| `actioned` | User took the recommended action |
| `dismissed` | User explicitly dismissed the insight |
| `snoozed` | User wants to be reminded later |

**Feedback endpoint:**

```http
PATCH /api/ai/insights/{insight_id}
{ "status": "actioned" | "dismissed" | "snoozed" }
```

On feedback, update `ai_insights` and optionally log to `activity_logs` for audit.

**Feedback loop for future tuning:**
- Track action rate per insight type and per confidence bucket.
- If `actioned_rate < 0.25` for `confidence_score > 0.90`, lower the model thresholds or review the SQL formulas.
- Store `actor_id` to learn which roles act on which insights.

---

## 7. Example Prompts & Expected Responses

### 7.1 Reorder recommendation

**Prompt (dashboard):** "What should I reorder this week?"

**Expected response:**

```text
Based on the last 30 days of sales at North Legon, you should reorder:

1. Nido milk powder 1kg — stock out in 2 days. Current: 8 units, velocity: 3.2/day. Suggested order: 42 units (supplier: Kantamanto Distributors).
2. Indomie instant noodles 150g — stock out in 3 days. Current: 45 packs, velocity: 15/day. Suggested order: 218 packs (supplier: Melcom Foods).

You have 6 additional items below their reorder threshold; see the full report in Inventory > Low Stock.
```

### 7.2 Anomaly detection

**Prompt (dashboard):** "Any unusual sales yesterday?"

**Expected response:**

```text
Yes. East Legon revenue on 2026-07-12 was GHS 4,200, which is 3.1x the 14-day average (GHS 1,355). The main driver was Indomie Instant Noodles 150g (GHS 890 additional revenue). Confidence: 92%.

This looks like a positive spike. No action required unless the uplift was from a one-off event.
```

### 7.3 Margin advisor

**Prompt (dashboard):** "Where are my margins shrinking?"

**Expected response:**

```text
Beverage margins shrank from 28% to 23.8% this week.

Affected products:
• Coca-Cola 1.5L — cost GHS 7.50, selling GHS 7.35 (loss). Suggested price: GHS 9.00–10.50.
• Voltic 1.5L — cost GHS 6.00, selling GHS 6.75 (margin 11%). Suggested price: GHS 7.50–9.00.

Consider reviewing discounts or supplier cost changes.
```

### 7.4 Natural-language Q&A

**Prompt (POS):** "How much stock do we have of Closeup toothpaste?"

**Expected response:**

```text
Closeup toothpaste 150g: 23 units at North Legon, 17 units at East Legon. Total across branches: 40 units. Reorder threshold: 15 units per branch.
```

---

## 8. Performance & Cost Considerations

### 8.1 Keep LLM calls cheap

1. **Summarised context.** The system prompt includes only:
   - Top 50 products by revenue (last 30 days).
   - Top 10 low-stock / reorder items.
   - Yesterday and 7-day revenue.
   - Top 3 anomalies and margin alerts.
   - Branch totals.

   Do not dump full `sales` / `sale_items` tables into the prompt.

2. **Cached snapshots.** Build a per-business `ledmi_business_snapshot` JSONB row every 10 minutes or on materialized-view refresh. The assistant reads this snapshot instead of running raw SQL.

   ```sql
   CREATE TABLE IF NOT EXISTS ledmi_business_snapshots (
       business_id UUID PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
       branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
       snapshot JSONB NOT NULL,
       computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
       expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '10 minutes'
   );
   CREATE INDEX IF NOT EXISTS idx_ledmi_snapshots_expiry ON ledmi_business_snapshots(expires_at);
   ```

3. **Prefer deterministic SQL insights.** Reorder, anomaly, and margin insights should be generated by SQL/RPC first. Use the LLM only to:
   - Summarise the day's insights in natural language.
   - Answer ad-hoc questions over the snapshot.
   - Format explanations.

4. **Token guardrails.** Enforce a `max_tokens` of 1,200 and strip redundant history beyond 10 turns.

### 8.2 Run heavy aggregations outside the request path

| Aggregation | Location | Cadence |
|---|---|---|
| `mv_daily_sales` refresh | Postgres / cron | Daily 06:00 GMT |
| `mv_stock_velocity` refresh | Postgres / cron | Daily 06:00 GMT + after each sync batch |
| `ledmi_business_snapshot` build | Edge Function / cron | Every 10 minutes or on demand |
| Critical alert evaluation | Edge Function triggered by DB trigger | Immediately after sync batch |
| Daily brief generation | Edge Function / cron | Daily 06:30 GMT |

**Request path (assistant chat):**
1. Check cache for `ledmi_business_snapshot`.
2. If expired, rebuild snapshot (not full aggregation) from materialized views.
3. Call NVIDIA NIM.

This keeps the chat response latency under ~2 seconds.

### 8.3 Scalability limits (MVP)

- Up to 20 branches per business.
- Up to 10,000 SKUs per business.
- 90 days of sales retained for velocity calculations.
- 10 reorder insights + 5 anomaly/margin insights surfaced per branch per day.

If a business exceeds these limits, add incremental refresh, partition `mv_daily_sales` by `business_id`, or move the feature store to the dedicated `feature_store` table.

---

## 9. Open Questions & Dependencies

1. **Branches table.** `database_architecture/01_schema.sql` does not yet contain `branches`. The Backend Architect (`agent_01`) must add it and link `sales`, `carts`, `inventory`, and `inventory_logs` to `branch_id` before this pipeline is wired.
2. **Supplier lead time.** The MVP schema has no `lead_time_days` on `suppliers`. The reorder formula uses a fixed 14-day horizon until that field is added.
3. **Push notification provider.** MNotify/Twilio/WhatsApp are P2 integrations. For MVP, `ai_insights.push_eligible` must be set but no external provider is called.
4. **AI key management.** `NVIDIA_API_KEY` is used by the Next.js server routes. The key is server-side only. A future iteration can move it to a Supabase Edge Function secret so the Flutter POS and dashboard share one endpoint.

---

## 10. Migration Checklist

- [ ] Add `branches` table and `branch_id` columns.
- [ ] Create `mv_daily_sales`, `v_inventory_snapshot`, and `mv_stock_velocity`.
- [ ] Create `ai_insights` and `ledmi_business_snapshots` tables.
- [ ] Create RPC functions: `ledmi_add_inventory_item`, `ledmi_update_stock_quantity`.
- [ ] Implement Edge Function `ledmi-assistant` or Next.js route `/api/ai/ask`.
- [ ] Implement daily cron for materialised-view refresh + brief generation.
- [ ] Implement sync-triggered critical alert job.
- [ ] Add RLS policies for `ai_insights` and `ledmi_business_snapshots`.
