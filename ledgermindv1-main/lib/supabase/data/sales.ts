import "server-only"
import { createServiceClient } from "@/lib/supabase/server"
import { getCurrentBusinessContext } from "./catalog"

export interface SaleItem {
  product_name: string
  quantity: number
  unit_price: number
  subtotal: number
}

export interface Sale {
  id: string
  invoice_number: string
  created_at: string
  cashier_email: string
  payment_method: string
  total: number
  items: SaleItem[]
}

export async function getSales(
  businessId: string,
  branchId?: string,
  from?: string,
  to?: string
): Promise<Sale[]> {
  const serviceClient = createServiceClient()

  let query = serviceClient
    .from("sales")
    .select(
      `
      id,
      created_at,
      invoices(invoice_number),
      payments(method, amount),
      cashier_id,
      sale_items(quantity, unit_price, subtotal, products(name))
    `
    )
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })

  if (branchId) {
    query = query.eq("branch_id", branchId)
  }
  if (from) {
    query = query.gte("created_at", from)
  }
  if (to) {
    query = query.lte("created_at", to)
  }

  const { data, error } = await query.limit(500)

  if (error) {
    throw new Error(error.message)
  }

  return (data as any[]).map((s) => ({
    id: s.id,
    invoice_number: s.invoices?.invoice_number || "-",
    created_at: s.created_at,
    cashier_email: "-",
    payment_method: s.payments?.method || "-",
    total: s.payments?.amount || 0,
    items: (s.sale_items as any[]).map((item) => ({
      product_name: item.products?.name || "Unknown",
      quantity: item.quantity,
      unit_price: item.unit_price,
      subtotal: item.subtotal,
    })),
  }))
}

export async function getSalesOverview(businessId: string) {
  const serviceClient = createServiceClient()
  const today = new Date()
  today.setHours(0, 0, 0, 0)

  const { data, error } = await serviceClient
    .from("sales")
    .select(
      `
      id,
      created_at,
      branch_id,
      payments(amount, method),
      branches(name)
    `
    )
    .eq("business_id", businessId)
    .gte("created_at", today.toISOString())

  if (error) {
    throw new Error(error.message)
  }

  let totalRevenue = 0
  let totalSales = 0
  const branchRevenue = new Map<string, { name: string; revenue: number; sales: number }>()

  for (const sale of data as any[]) {
    const amount = sale.payments?.amount || 0
    totalRevenue += amount
    totalSales += 1

    const branchId = sale.branch_id
    const branchName = sale.branches?.name || "Unknown"
    const existing = branchRevenue.get(branchId) || { name: branchName, revenue: 0, sales: 0 }
    existing.revenue += amount
    existing.sales += 1
    branchRevenue.set(branchId, existing)
  }

  return {
    totalRevenue,
    totalSales,
    branchRevenue: Array.from(branchRevenue.values()),
  }
}

export async function getCurrentBusinessContextForSales() {
  return getCurrentBusinessContext()
}
