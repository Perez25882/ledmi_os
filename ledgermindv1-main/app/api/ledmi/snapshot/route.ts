import { NextResponse } from "next/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage, getScopedBranchFilter } from "@/lib/supabase/permissions"
import { getSelectedBranchId } from "@/lib/supabase/selected-branch"
import { getInsights } from "@/lib/supabase/data/insights"
import { askNVIDIA } from "@/lib/nvidia-ai"
import { createServerClientForUser } from "@/lib/supabase/server"

interface QuickSaleToday {
  name: string
  times_sold: number
  total_revenue: number
}

interface SnapshotData {
  today_revenue: number
  today_sales_count: number
  average_basket: number
  top_products: Array<{ product_name: string; total_quantity: number; total_revenue: number }>
  low_stock: Array<{
    product_name: string
    current_quantity: number
    avg_daily_units: number
    days_until_stockout: number | null
  }>
  quick_sales_today: QuickSaleToday[]
  seven_day_avg_revenue: number
  revenue_vs_avg_percent: number | null
  day_of_week: string
}

function startOfTodayISO(): string {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  return d.toISOString()
}

function daysAgoISO(days: number): string {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - days)
  return d.toISOString()
}

async function getSevenDayAverageRevenue(
  businessId: string,
  branchId?: string
): Promise<number> {
  const client = await createServerClientForUser()
  const since = daysAgoISO(7)

  let query = client
    .from("sales")
    .select("created_at, payments(amount)")
    .eq("business_id", businessId)
    .gte("created_at", since)
    .lt("created_at", startOfTodayISO())

  if (branchId) {
    query = query.eq("branch_id", branchId)
  }

  const { data, error } = await query.limit(1000)
  if (error) throw new Error(error.message)

  const rows = (data as any[]) ?? []
  const byDate = new Map<string, number>()
  for (const row of rows) {
    const amount = Number(row.payments?.amount ?? 0)
    const dateKey = (row.created_at as string).slice(0, 10)
    byDate.set(dateKey, (byDate.get(dateKey) ?? 0) + amount)
  }

  if (byDate.size === 0) return 0
  const total = Array.from(byDate.values()).reduce((a, b) => a + b, 0)
  return total / byDate.size
}

async function getQuickSalesToday(
  businessId: string,
  branchId?: string
): Promise<QuickSaleToday[]> {
  const client = await createServerClientForUser()
  const startToday = startOfTodayISO()

  let query = client
    .from("sale_items")
    .select(
      "quick_sale_name, quantity, unit_price, subtotal, sales!inner(created_at, branch_id, business_id)"
    )
    .eq("is_quick_sale", true)
    .not("quick_sale_name", "is", null)
    .eq("sales.business_id", businessId)
    .gte("sales.created_at", startToday)

  if (branchId) {
    query = query.eq("sales.branch_id", branchId)
  }

  const { data, error } = await query.limit(500)
  if (error) throw new Error(error.message)

  const rows = (data as any[]) ?? []
  const groups = new Map<string, QuickSaleToday>()
  for (const row of rows) {
    const name = (row.quick_sale_name as string) || "Unknown"
    const subtotal = Number(row.subtotal != null ? row.subtotal : row.quantity * row.unit_price)
    const existing = groups.get(name) ?? { name, times_sold: 0, total_revenue: 0 }
    existing.times_sold += 1
    existing.total_revenue += subtotal
    groups.set(name, existing)
  }

  return Array.from(groups.values()).sort((a, b) => b.times_sold - a.times_sold)
}

function buildSystemPrompt(data: SnapshotData): string {
  const topProducts =
    data.top_products
      .map((p) => `${p.product_name}: ${p.total_quantity} units, GHS ${p.total_revenue.toFixed(2)}`)
      .join("\n") || "None"

  const lowStock =
    data.low_stock
      .map(
        (l) =>
          `${l.product_name}: ${l.current_quantity} left, ~${l.avg_daily_units.toFixed(1)}/day${
            l.days_until_stockout !== null
              ? `, stockout in ${l.days_until_stockout.toFixed(1)} days`
              : ""
          }`
      )
      .join("\n") || "None"

  const quickSales =
    data.quick_sales_today
      .map((q) => `${q.name}: ${q.times_sold} time(s), GHS ${q.total_revenue.toFixed(2)}`)
      .join("\n") || "None"

  const vsAvg =
    data.revenue_vs_avg_percent !== null
      ? `${data.revenue_vs_avg_percent >= 0 ? "+" : ""}${data.revenue_vs_avg_percent.toFixed(1)}% vs 7-day average (GHS ${data.seven_day_avg_revenue.toFixed(2)})`
      : "no prior data to compare"

  return `You are Ledmi, a retail business analyst for LedgerMind OS. Given the following business data for today (${data.day_of_week}), write a 3-4 sentence snapshot that highlights what's notable, what needs attention, and one actionable suggestion. Be specific with numbers. Be conversational, not robotic. Do not use bullet points — write natural sentences. Ground every claim in the numbers provided; never invent data.

Today's revenue: GHS ${data.today_revenue.toFixed(2)} across ${data.today_sales_count} sales. Average basket: GHS ${data.average_basket.toFixed(2)}. Revenue is ${vsAvg}.

Top products today (by revenue):
${topProducts}

Low stock items:
${lowStock}

Quick sales today (items sold outside the catalog):
${quickSales}

Write the snapshot now. 3-4 sentences. No bullet points. No preamble.`
}

function fallbackSnapshot(data: SnapshotData): string {
  const parts: string[] = []

  if (data.today_sales_count === 0) {
    parts.push("No sales have been recorded yet today.")
  } else {
    const vsAvg =
      data.revenue_vs_avg_percent !== null
        ? ` That's ${data.revenue_vs_avg_percent >= 0 ? "up" : "down"} ${Math.abs(data.revenue_vs_avg_percent).toFixed(0)}% versus your 7-day average.`
        : ""
    parts.push(
      `Today you've made GHS ${data.today_revenue.toFixed(2)} across ${data.today_sales_count} sales, with an average basket of GHS ${data.average_basket.toFixed(2)}.${vsAvg}`
    )

    if (data.top_products.length > 0) {
      const top = data.top_products[0]
      parts.push(
        `Your top seller today is ${top.product_name} (${top.total_quantity} units, GHS ${top.total_revenue.toFixed(2)}).`
      )
    }
  }

  if (data.low_stock.length > 0) {
    const urgent = data.low_stock.slice(0, 2)
    const desc = urgent
      .map((l) => `${l.product_name} (${l.current_quantity} left)`)
      .join(", ")
    parts.push(`${desc} ${urgent.length === 1 ? "is" : "are"} running low and may need reordering.`)
  }

  if (data.quick_sales_today.length > 0) {
    const qs = data.quick_sales_today[0]
    parts.push(
      `You had ${data.quick_sales_today.length} quick sale${data.quick_sales_today.length === 1 ? "" : "s"} today — '${qs.name}' was sold ${qs.times_sold} time${qs.times_sold === 1 ? "" : "s"}, consider adding it to your catalog.`
    )
  }

  if (parts.length === 0) {
    parts.push("Your business is running smoothly — no notable items need attention right now.")
  }

  return parts.join(" ")
}

export async function GET() {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    if (!canAccessPage(context.roleName, "overview")) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const selectedBranchId = await getSelectedBranchId(context)
    const { branchId: scopedBranchId } = getScopedBranchFilter(context, selectedBranchId)
    const effectiveBranchId = scopedBranchId ?? context.branchId

    const [insights, sevenDayAvg, quickSalesToday] = await Promise.all([
      getInsights(context.businessId, effectiveBranchId),
      getSevenDayAverageRevenue(context.businessId, scopedBranchId),
      getQuickSalesToday(context.businessId, scopedBranchId),
    ])

    const todayRevenue = insights.today_summary.revenue
    const revenueVsAvg =
      sevenDayAvg > 0 ? ((todayRevenue - sevenDayAvg) / sevenDayAvg) * 100 : null

    const snapshotData: SnapshotData = {
      today_revenue: todayRevenue,
      today_sales_count: insights.today_summary.sales_count,
      average_basket: insights.today_summary.average_order_value,
      top_products: insights.today_summary.top_products.map((p) => ({
        product_name: p.product_name,
        total_quantity: p.total_quantity,
        total_revenue: p.total_revenue,
      })),
      low_stock: insights.reorder_suggestions
        .sort(
          (a, b) =>
            (a.days_until_stockout ?? Infinity) - (b.days_until_stockout ?? Infinity)
        )
        .slice(0, 5)
        .map((r) => ({
          product_name: r.product_name,
          current_quantity: r.current_quantity,
          avg_daily_units: r.avg_daily_units,
          days_until_stockout: r.days_until_stockout,
        })),
      quick_sales_today: quickSalesToday,
      seven_day_avg_revenue: sevenDayAvg,
      revenue_vs_avg_percent: revenueVsAvg,
      day_of_week: new Date().toLocaleDateString("en-US", { weekday: "long" }),
    }

    let snapshot: string
    try {
      const aiText = await askNVIDIA(buildSystemPrompt(snapshotData), "Write the snapshot.")
      snapshot = aiText ?? fallbackSnapshot(snapshotData)
    } catch (err) {
      console.error("Snapshot AI generation failed:", err)
      snapshot = fallbackSnapshot(snapshotData)
    }

    return NextResponse.json({ snapshot })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
