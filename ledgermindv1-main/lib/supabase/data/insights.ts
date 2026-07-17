import "server-only"
import { createServiceClient } from "@/lib/supabase/server"

export interface ReorderSuggestion {
  product_id: string
  product_name: string
  branch_id: string
  branch_name: string
  current_quantity: number
  reorder_level: number
  suggested_order: number
}

export interface MarginInsight {
  product_id: string
  product_name: string
  selling_price: number
  cost_price: number
  margin_percent: number
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
}

export async function getInsights(
  businessId: string,
  branchId: string
): Promise<LedmiInsights> {
  const serviceClient = createServiceClient()

  const today = new Date()
  today.setHours(0, 0, 0, 0)

  const [inventoryRes, productsRes, salesRes] = await Promise.all([
    serviceClient
      .from("inventory")
      .select("product_id, quantity, reorder_level, branch_id, branches(name), products(name)")
      .eq("business_id", businessId)
      .eq("branch_id", branchId),
    serviceClient
      .from("products")
      .select("id, name, selling_price, cost_price")
      .eq("business_id", businessId)
      .is("deleted_at", null),
    serviceClient
      .from("sales")
      .select(
        `
        id,
        payments(amount),
        sale_items(quantity, unit_price, product_id, products(name))
      `
      )
      .eq("business_id", businessId)
      .eq("branch_id", branchId)
      .gte("created_at", today.toISOString()),
  ])

  if (inventoryRes.error) throw new Error(inventoryRes.error.message)
  if (productsRes.error) throw new Error(productsRes.error.message)
  if (salesRes.error) throw new Error(salesRes.error.message)

  const inventory = inventoryRes.data as any[]
  const products = productsRes.data as any[]
  const sales = salesRes.data as any[]

  const reorderSuggestions: ReorderSuggestion[] = inventory
    .filter((i) => i.quantity <= i.reorder_level)
    .map((i) => ({
      product_id: i.product_id,
      product_name: i.products?.name || "Unknown",
      branch_id: i.branch_id,
      branch_name: i.branches?.name || "Unknown",
      current_quantity: i.quantity,
      reorder_level: i.reorder_level,
      suggested_order: Math.max(i.reorder_level * 2 - i.quantity, 10),
    }))

  const lowMarginProducts: MarginInsight[] = products
    .filter((p) => p.selling_price > 0 && (p.selling_price - p.cost_price) / p.selling_price < 0.1)
    .map((p) => ({
      product_id: p.id,
      product_name: p.name,
      selling_price: p.selling_price,
      cost_price: p.cost_price,
      margin_percent: ((p.selling_price - p.cost_price) / p.selling_price) * 100,
    }))

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

  const anomalies: string[] = []
  if (reorderSuggestions.length > 0) {
    anomalies.push(`${reorderSuggestions.length} products are at or below reorder level.`)
  }
  if (lowMarginProducts.length > 0) {
    anomalies.push(`${lowMarginProducts.length} products have a margin below 10%.`)
  }
  if (salesCount === 0) {
    anomalies.push("No sales recorded today.")
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
  }
}
