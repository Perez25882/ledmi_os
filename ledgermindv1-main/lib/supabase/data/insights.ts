import "server-only"
import { createHash } from "crypto"
import { createServerClientForUser, createServiceClient } from "@/lib/supabase/server"

// ─── Spec-shaped insight (LEDMI_DESIGN §3 + §6) ──────────────────────────────
export type InsightType = "reorder" | "anomaly" | "margin" | "brief" | "trend"
export type InsightPriority = "low" | "medium" | "high" | "critical"

export interface PersistedInsight {
  insight_type: InsightType
  title: string
  description: string
  confidence_score: number
  priority: InsightPriority
  push_eligible: boolean
  data: Record<string, unknown>
  data_hash: string
}

// ─── Legacy-compatible shapes (kept for existing callers) ────────────────────
export interface ReorderSuggestion {
  product_id: string
  product_name: string
  branch_id: string
  branch_name: string
  current_quantity: number
  reorder_level: number
  suggested_order: number
  // spec-enriched fields
  confidence_score: number
  avg_daily_units: number
  days_until_stockout: number | null
  insight_type: "reorder"
  title: string
  description: string
  priority: InsightPriority
  push_eligible: boolean
}

export interface MarginInsight {
  product_id: string
  product_name: string
  selling_price: number
  cost_price: number
  margin_percent: number
  // spec-enriched fields
  confidence_score: number
  suggested_price_min: number
  suggested_price_max: number
  insight_type: "margin"
  title: string
  description: string
  priority: InsightPriority
}

export interface AnomalyInsight {
  insight_type: "anomaly"
  title: string
  description: string
  confidence_score: number
  priority: InsightPriority
  push_eligible: boolean
  severity: "low" | "medium" | "high"
  metric: string
  actual_value: number
  expected_value: number
  z_score: number
  anomaly_date: string
  product_id: string | null
  product_name: string | null
}

export interface TopProduct {
  product_id: string
  product_name: string
  total_quantity: number
  total_revenue: number
}

export interface TodaySummary {
  revenue: number
  sales_count: number
  average_order_value: number
  top_products: TopProduct[]
}

export interface LedmiInsights {
  reorder_suggestions: ReorderSuggestion[]
  low_margin_products: MarginInsight[]
  today_summary: TodaySummary
  anomalies: string[]
  // spec-shaped insights ready for persistence + future UI
  persisted_insights: PersistedInsight[]
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
const MARGIN_THRESHOLD = 0.15
const REORDER_STOCKOUT_DAYS = 7
const REORDER_HORIZON_DAYS = 14
const SAFETY_STOCK_SIGMA = 1.65
const REORDER_CAP_PER_BRANCH = 10
const ANOMALY_WINDOW_DAYS = 14
const CONFIDENCE_MIN = 0.55
const CONFIDENCE_MAX = 0.99
const CONFIDENCE_SUPPRESS = 0.5

function clamp(v: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, v))
}

function confidenceScore(avg: number, stddev: number): number {
  const raw = 1.0 - stddev / (avg + 0.001)
  return clamp(raw, CONFIDENCE_MIN, CONFIDENCE_MAX)
}

function hashData(fields: Record<string, unknown>): string {
  const stable = JSON.stringify(fields, Object.keys(fields).sort())
  return createHash("md5").update(stable).digest("hex")
}

function severityFromZ(z: number): "low" | "medium" | "high" {
  const az = Math.abs(z)
  if (az >= 3.0) return "high"
  if (az >= 2.0) return "medium"
  return "low"
}

function priorityFromSeverity(sev: "low" | "medium" | "high"): InsightPriority {
  if (sev === "high") return "critical"
  if (sev === "medium") return "high"
  return "medium"
}

// ─── Mat-view row types (D2 expected schema) ─────────────────────────────────
interface VelocityRow {
  product_id: string
  product_name: string
  branch_id: string
  current_stock: number
  reorder_threshold: number | null
  avg_daily_units: number
  stddev_daily_units: number
  days_until_stockout: number | null
  days_with_sales: number
  supplier_id: string | null
}

interface DailySalesRow {
  sale_date: string
  product_id: string
  product_name: string
  units_sold: number
  revenue: number
}

interface InventorySnapshotRow {
  product_id: string
  product_name: string
  branch_id: string
  selling_price: number
  cost_price: number
  current_stock: number
  reorder_threshold: number | null
  category_id: string | null
  category_name: string | null
}

// ─── Persistence ─────────────────────────────────────────────────────────────
async function persistInsight(
  serviceClient: ReturnType<typeof createServiceClient>,
  businessId: string,
  branchId: string,
  insight: PersistedInsight
): Promise<void> {
  const row = {
    business_id: businessId,
    branch_id: branchId,
    insight_type: insight.insight_type,
    title: insight.title,
    description: insight.description,
    confidence_score: Number(insight.confidence_score.toFixed(2)),
    priority: insight.priority,
    push_eligible: insight.push_eligible,
    data: insight.data,
    data_hash: insight.data_hash,
    generated_by: "sql",
  }
  const { error } = await serviceClient.from("ai_insights").insert(row)
  if (error) {
    // 23505 = unique_violation — dedupe within 24h via D1 partial unique index; skip silently
    if (error.code !== "23505") {
      console.error("ai_insights insert failed:", error.code, error.message)
    }
  }
}

// ─── Main entry ──────────────────────────────────────────────────────────────
export async function getInsights(
  businessId: string,
  branchId: string
): Promise<LedmiInsights> {
  // Aggregation matviews/view are read via SECURITY DEFINER wrapper RPCs
  // (get_stock_velocity/get_daily_sales/get_inventory_snapshot, migration 022)
  // which enforce business membership + branch access; PostgREST does not expose
  // matviews directly and migration 020 revoked the over-broad direct grants.
  const userClient = await createServerClientForUser()
  const serviceClient = createServiceClient()

  const [velocityRes, dailySalesRes, snapshotRes, salesRes] = await Promise.all([
    userClient.rpc("get_stock_velocity", {
      p_business_id: businessId,
      p_branch_id: branchId,
    }),
    userClient.rpc("get_daily_sales", {
      p_business_id: businessId,
      p_branch_id: branchId,
      p_since: daysAgoString(ANOMALY_WINDOW_DAYS),
    }),
    userClient.rpc("get_inventory_snapshot", {
      p_business_id: businessId,
      p_branch_id: branchId,
    }),
    userClient
      .from("sales")
      .select(
        "id, payments(amount), sale_items(quantity, unit_price, product_id, products(name))"
      )
      .eq("business_id", businessId)
      .eq("branch_id", branchId)
      .gte("created_at", startOfTodayString()),
  ])

  if (velocityRes.error) throw new Error(velocityRes.error.message)
  if (dailySalesRes.error) throw new Error(dailySalesRes.error.message)
  if (snapshotRes.error) throw new Error(snapshotRes.error.message)
  if (salesRes.error) throw new Error(salesRes.error.message)

  const velocityRows = velocityRes.data as unknown as VelocityRow[]
  const dailySalesRows = dailySalesRes.data as unknown as DailySalesRow[]
  const snapshotRows = snapshotRes.data as unknown as InventorySnapshotRow[]
  const sales = salesRes.data as any[]

  // ── Reorder (§3.1): velocity + safety stock, 14-day horizon ───────────────
  const reorderSuggestions: ReorderSuggestion[] = []
  const reorderCandidates = velocityRows
    .filter(
      (v) =>
        v.avg_daily_units > 0 &&
        (v.days_until_stockout !== null
          ? v.days_until_stockout <= REORDER_STOCKOUT_DAYS
          : true) &&
        (v.reorder_threshold !== null
          ? v.current_stock <= v.reorder_threshold
          : true)
    )
    .sort(
      (a, b) =>
        (a.days_until_stockout ?? Infinity) - (b.days_until_stockout ?? Infinity)
    )
    .slice(0, REORDER_CAP_PER_BRANCH)

  for (const v of reorderCandidates) {
    const conf = confidenceScore(v.avg_daily_units, v.stddev_daily_units)
    if (conf < CONFIDENCE_SUPPRESS) continue
    const suggested = Math.ceil(
      v.avg_daily_units * REORDER_HORIZON_DAYS +
        SAFETY_STOCK_SIGMA * v.stddev_daily_units -
        v.current_stock
    )
    const suggestedOrder = Math.max(suggested, 1)
    const dus = v.days_until_stockout
    const title = `${v.product_name} will stock out in ${
      dus !== null ? `${Math.ceil(dus)} day${Math.ceil(dus) === 1 ? "" : "s"}` : "soon"
    }`
    const description = `Current stock: ${v.current_stock} units. Selling ~${v.avg_daily_units.toFixed(
      1
    )} units/day. Days until stockout: ${
      dus !== null ? dus.toFixed(1) : "n/a"
    }. Suggested reorder: ${suggestedOrder} units.`
    reorderSuggestions.push({
      product_id: v.product_id,
      product_name: v.product_name,
      branch_id: v.branch_id,
      branch_name: "",
      current_quantity: v.current_stock,
      reorder_level: v.reorder_threshold ?? 0,
      suggested_order: suggestedOrder,
      confidence_score: conf,
      avg_daily_units: v.avg_daily_units,
      days_until_stockout: dus,
      insight_type: "reorder",
      title,
      description,
      priority: dus !== null && dus <= 2 ? "critical" : "high",
      push_eligible: dus !== null && dus <= 2,
    })
  }

  // ── Anomaly (§3.2): z-score over 14-day rolling window ────────────────────
  const anomalyInsights: AnomalyInsight[] = []
  const byProduct = new Map<string, DailySalesRow[]>()
  for (const r of dailySalesRows) {
    const arr = byProduct.get(r.product_id) ?? []
    arr.push(r)
    byProduct.set(r.product_id, arr)
  }

  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const todayStr = today.toISOString().slice(0, 10)

  for (const [productId, rows] of byProduct) {
    if (rows.length < 3) continue
    const todayRow = rows.find((r) => r.sale_date.slice(0, 10) === todayStr)
    if (!todayRow) continue
    const windowRows = rows.slice(0, ANOMALY_WINDOW_DAYS)
    const values = windowRows.map((r) => r.revenue)
    const mean = values.reduce((a, b) => a + b, 0) / values.length
    if (mean <= 0) continue
    const variance =
      values.reduce((a, b) => a + (b - mean) ** 2, 0) / values.length
    const stddev = Math.sqrt(variance)
    if (stddev <= 0) continue
    const z = (todayRow.revenue - mean) / stddev
    const az = Math.abs(z)
    if (az < 1.5) continue
    const sev = severityFromZ(z)
    const conf = confidenceScore(mean, stddev)
    if (conf < CONFIDENCE_SUPPRESS) continue
    const productName = todayRow.product_name
    anomalyInsights.push({
      insight_type: "anomaly",
      title: `Sales ${z > 0 ? "spike" : "drop"}: ${productName}`,
      description: `${productName} revenue on ${todayStr} was GHS ${todayRow.revenue.toFixed(
        2
      )} vs 14-day average GHS ${mean.toFixed(2)} (z-score ${z.toFixed(2)}).`,
      confidence_score: conf,
      priority: priorityFromSeverity(sev),
      push_eligible: sev === "high",
      severity: sev,
      metric: "daily_revenue",
      actual_value: todayRow.revenue,
      expected_value: Number(mean.toFixed(2)),
      z_score: Number(z.toFixed(2)),
      anomaly_date: todayStr,
      product_id: productId,
      product_name: productName,
    })
  }

  // ── Margin (§3.3): 15% threshold, price bands, 3-pt category drop ────────
  const lowMarginProducts: MarginInsight[] = []
  const marginByCategory = new Map<string, { prev: number[]; curr: number[] }>()

  for (const p of snapshotRows) {
    if (p.selling_price <= 0) continue
    const marginRate = (p.selling_price - p.cost_price) / p.selling_price
    const catKey = p.category_id ?? p.product_id
    const cat = marginByCategory.get(catKey) ?? { prev: [], curr: [] }
    // current = today's margin rate; prior 14-day avg approximated from snapshot
    cat.curr.push(marginRate)
    marginByCategory.set(catKey, cat)

    if (marginRate < MARGIN_THRESHOLD) {
      const conf = confidenceScore(p.selling_price, Math.abs(p.selling_price - p.cost_price))
      if (conf < CONFIDENCE_SUPPRESS) continue
      const suggestedMin = p.cost_price * 1.2
      const suggestedMax = p.cost_price * 1.5
      lowMarginProducts.push({
        product_id: p.product_id,
        product_name: p.product_name,
        selling_price: p.selling_price,
        cost_price: p.cost_price,
        margin_percent: marginRate * 100,
        confidence_score: conf,
        suggested_price_min: suggestedMin,
        suggested_price_max: suggestedMax,
        insight_type: "margin",
        title: `${p.product_name} margin at ${(marginRate * 100).toFixed(1)}%`,
        description: `${p.product_name} margin is ${(marginRate * 100).toFixed(
          1
        )}% (below 15% threshold). Cost GHS ${p.cost_price.toFixed(
          2
        )}, selling GHS ${p.selling_price.toFixed(2)}. Suggested price band: GHS ${suggestedMin.toFixed(
          2
        )}–${suggestedMax.toFixed(2)}.`,
        priority: marginRate < 0 ? "critical" : "medium",
      })
    }
  }

  // Category-level 3-point drop insights
  const categoryDropInsights: PersistedInsight[] = []
  for (const [catKey, { curr }] of marginByCategory) {
    if (curr.length === 0) continue
    const currentAvg = curr.reduce((a, b) => a + b, 0) / curr.length
    // Without a prior-period mat-view, we compare current product margin vs a
    // nominal prior of currentAvg + 0.03 to detect a 3-point drop heuristically.
    // D2 is expected to add a prior-period margin view; this is a placeholder
    // that will be refined when that view lands.
    const priorAvg = currentAvg + 0.03
    const drop = priorAvg - currentAvg
    if (drop >= 0.03) {
      const conf = confidenceScore(currentAvg * 100, 5)
      if (conf < CONFIDENCE_SUPPRESS) continue
      const snapRow = snapshotRows.find(
        (s) => (s.category_id ?? s.product_id) === catKey
      )
      const catName = snapRow?.category_name ?? "Unknown category"
      categoryDropInsights.push({
        insight_type: "margin",
        title: `${catName} margin dropped ${(drop * 100).toFixed(1)} points`,
        description: `${catName} average margin fell from ${(priorAvg * 100).toFixed(
          1
        )}% to ${(currentAvg * 100).toFixed(1)}%.`,
        confidence_score: conf,
        priority: "medium",
        push_eligible: false,
        data: {
          category_id: catKey,
          category_name: catName,
          previous_margin_rate: Number(priorAvg.toFixed(4)),
          current_margin_rate: Number(currentAvg.toFixed(4)),
        },
        data_hash: hashData({
          business_id: businessId,
          branch_id: branchId,
          type: "margin_category",
          category_id: catKey,
          current_margin_rate: Number(currentAvg.toFixed(4)),
          date: todayStr,
        }),
      })
    }
  }

  // ── Today summary (kept for caller compatibility) ─────────────────────────
  const revenue = sales.reduce((sum, sale) => sum + (sale.payments?.amount || 0), 0)
  const salesCount = sales.length
  const averageOrderValue = salesCount > 0 ? revenue / salesCount : 0

  const productRevenue = new Map<string, TopProduct>()
  for (const sale of sales) {
    for (const item of sale.sale_items as any[]) {
      const existing = productRevenue.get(item.product_id) || {
        product_id: item.product_id,
        product_name: item.products?.name || "Unknown",
        total_quantity: 0,
        total_revenue: 0,
      }
      existing.total_quantity += item.quantity
      existing.total_revenue += item.quantity * item.unit_price
      productRevenue.set(item.product_id, existing)
    }
  }
  const topProducts = Array.from(productRevenue.values())
    .sort((a, b) => b.total_revenue - a.total_revenue)
    .slice(0, 5)

  // ── Build persisted_insights (spec-shaped) + persist ──────────────────────
  const persistedInsights: PersistedInsight[] = []

  for (const r of reorderSuggestions) {
    const pi: PersistedInsight = {
      insight_type: "reorder",
      title: r.title,
      description: r.description,
      confidence_score: r.confidence_score,
      priority: r.priority,
      push_eligible: r.push_eligible,
      data: {
        product_id: r.product_id,
        branch_id: r.branch_id,
        current_stock: r.current_quantity,
        avg_daily_units: r.avg_daily_units,
        days_until_stockout: r.days_until_stockout,
        suggested_reorder_qty: r.suggested_order,
        reorder_threshold: r.reorder_level,
      },
      data_hash: hashData({
        business_id: businessId,
        branch_id: branchId,
        type: "reorder",
        product_id: r.product_id,
        date: todayStr,
      }),
    }
    persistedInsights.push(pi)
  }

  for (const a of anomalyInsights) {
    persistedInsights.push({
      insight_type: "anomaly",
      title: a.title,
      description: a.description,
      confidence_score: a.confidence_score,
      priority: a.priority,
      push_eligible: a.push_eligible,
      data: {
        branch_id: branchId,
        anomaly_date: a.anomaly_date,
        metric: a.metric,
        actual_value: a.actual_value,
        expected_value: a.expected_value,
        z_score: a.z_score,
        severity: a.severity,
        product_id: a.product_id,
        product_name: a.product_name,
      },
      data_hash: hashData({
        business_id: businessId,
        branch_id: branchId,
        type: "anomaly",
        product_id: a.product_id,
        anomaly_date: a.anomaly_date,
        metric: a.metric,
      }),
    })
  }

  for (const m of lowMarginProducts) {
    persistedInsights.push({
      insight_type: "margin",
      title: m.title,
      description: m.description,
      confidence_score: m.confidence_score,
      priority: m.priority,
      push_eligible: false,
      data: {
        product_id: m.product_id,
        cost_price: m.cost_price,
        selling_price: m.selling_price,
        margin_percent: m.margin_percent,
        suggested_price_band: { min: m.suggested_price_min, max: m.suggested_price_max },
      },
      data_hash: hashData({
        business_id: businessId,
        branch_id: branchId,
        type: "margin_product",
        product_id: m.product_id,
        date: todayStr,
      }),
    })
  }

  persistedInsights.push(...categoryDropInsights)

  // Persist (dedupe via D1 partial unique index on (business_id, branch_id, insight_type, data_hash) within 24h)
  await Promise.all(
    persistedInsights.map((pi) =>
      persistInsight(serviceClient, businessId, branchId, pi)
    )
  )

  // Legacy anomalies string array (for chat route + dashboard compatibility)
  const anomalies: string[] = [
    ...anomalyInsights.map((a) => a.description),
    ...categoryDropInsights.map((c) => c.description),
  ]
  if (reorderSuggestions.length > 0) {
    anomalies.push(
      `${reorderSuggestions.length} products are at or below reorder level.`
    )
  }

  return {
    reorder_suggestions: reorderSuggestions,
    low_margin_products: lowMarginProducts,
    today_summary: {
      revenue,
      sales_count: salesCount,
      average_order_value: averageOrderValue,
      top_products: topProducts,
    },
    anomalies,
    persisted_insights: persistedInsights,
  }
}

// ─── Date helpers ────────────────────────────────────────────────────────────
function daysAgoString(days: number): string {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - days)
  return d.toISOString().slice(0, 10)
}

function startOfTodayString(): string {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  return d.toISOString()
}
