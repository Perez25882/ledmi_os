import { NextResponse } from "next/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import { askNVIDIA } from "@/lib/nvidia-ai"

export const runtime = "nodejs"

interface RawPrediction {
  product_id: string
  name: string
  current_stock: number
  daily_velocity: number
  days_until_stockout: number | null
  suggested_reorder: number
  urgency: "critical" | "warning" | "info"
  last_sold_hours_ago: number | null
}

function urgencyFor(daysUntilStockout: number | null): "critical" | "warning" | "info" {
  if (daysUntilStockout === null) return "info"
  if (daysUntilStockout < 1) return "critical"
  if (daysUntilStockout < 3) return "warning"
  return "info"
}

export async function GET() {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    if (!canAccessPage(context.roleName, "inventory")) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const { businessId, branchId } = context

    // Low-stock items: inventory.quantity <= inventory.reorder_level.
    const client = await import("@/lib/supabase/server").then((m) =>
      m.createServerClientForUser()
    )

    const { data: inventoryRows, error: invError } = await client
      .from("inventory")
      .select(
        `product_id, quantity, reorder_level, products(id, name)`
      )
      .eq("business_id", businessId)
      .eq("branch_id", branchId)
      .filter("quantity", "lte", "reorder_level")

    if (invError) {
      return NextResponse.json({ error: invError.message }, { status: 500 })
    }

    if (!inventoryRows || inventoryRows.length === 0) {
      return NextResponse.json({ predictions: [] })
    }

    const since = new Date()
    since.setDate(since.getDate() - 7)
    const sinceIso = since.toISOString()

    const predictions: RawPrediction[] = []

    for (const row of inventoryRows as any[]) {
      const product = row.products as any
      if (!product) continue
      const productId = product.id as string
      const name = (product.name as string) ?? "Unknown"
      const currentStock = Number(row.quantity ?? 0)

      // Last 7 days of sales for this product.
      const { data: saleRows } = await client
        .from("sale_items")
        .select(`quantity, sale:sales!inner(created_at)`)
        .eq("product_id", productId)
        .eq("sale.business_id", businessId)
        .eq("sale.branch_id", branchId)
        .gte("sale.created_at", sinceIso)

      let totalSold = 0
      let lastSoldAt: Date | null = null
      for (const si of (saleRows as any[]) ?? []) {
        totalSold += Number(si.quantity ?? 0)
        const created = si.sale?.created_at as string | undefined
        if (created) {
          const d = new Date(created)
          if (!lastSoldAt || d > lastSoldAt) lastSoldAt = d
        }
      }

      const dailyVelocity = totalSold / 7
      const daysUntilStockout =
        dailyVelocity > 0 ? currentStock / dailyVelocity : null
      const suggestedReorder = Math.max(1, Math.round(dailyVelocity * 7))
      const lastSoldHoursAgo = lastSoldAt
        ? Math.round((Date.now() - lastSoldAt.getTime()) / 3_600_000)
        : null

      predictions.push({
        product_id: productId,
        name,
        current_stock: currentStock,
        daily_velocity: Number(dailyVelocity.toFixed(2)),
        days_until_stockout:
          daysUntilStockout === null
            ? null
            : Number(daysUntilStockout.toFixed(2)),
        suggested_reorder: suggestedReorder,
        urgency: urgencyFor(daysUntilStockout),
        last_sold_hours_ago: lastSoldHoursAgo,
      })
    }

    // Sort by urgency: critical → warning → info, then soonest stockout.
    const order = { critical: 0, warning: 1, info: 2 }
    predictions.sort((a, b) => {
      const u = order[a.urgency] - order[b.urgency]
      if (u !== 0) return u
      const ad = a.days_until_stockout ?? Infinity
      const bd = b.days_until_stockout ?? Infinity
      return ad - bd
    })

    // Enrich with AI insights (graceful fallback if unavailable).
    const aiInsights: Record<string, string> = {}
    try {
      const systemPrompt =
        "You are Ledmi, an AI retail assistant for LedgerMind OS. For each low-stock product, write a one-line insight about the stockout risk. Be specific and urgent, grounded in the numbers. Format as a JSON array of {product_id, insight_text}."
      const userPrompt = `Low-stock products:\n${JSON.stringify(
        predictions.map((p) => ({
          product_id: p.product_id,
          name: p.name,
          current_stock: p.current_stock,
          daily_velocity: p.daily_velocity,
          days_until_stockout: p.days_until_stockout,
        })),
        null,
        2
      )}\n\nReturn ONLY a JSON array.`

      const raw = await askNVIDIA(systemPrompt, userPrompt)
      if (raw) {
        const cleaned = raw
          .replace(/^```(?:json)?\s*/, "")
          .replace(/\s*```$/, "")
          .trim()
        const parsed = JSON.parse(cleaned) as any[]
        for (const item of parsed) {
          if (item && typeof item.product_id === "string" && typeof item.insight_text === "string") {
            aiInsights[item.product_id] = item.insight_text
          }
        }
      }
    } catch {
      // AI call failed — return raw calculations without ai_insight.
    }

    const result = predictions.map((p) => ({
      ...p,
      ai_insight: aiInsights[p.product_id] ?? null,
    }))

    return NextResponse.json({ predictions: result })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
