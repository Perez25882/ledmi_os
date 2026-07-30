import "server-only"
import { createServerClientForUser, createServiceClient } from "@/lib/supabase/server"
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

// auth.users is not readable under RLS, so the admin API is the only email
// source available without a migration. Scope is preserved: only cashier_ids
// taken from rows already RLS-filtered to the caller's business are looked up.
export async function resolveCashierEmails(cashierIds: string[]): Promise<Map<string, string>> {
  const unique = [...new Set(cashierIds.filter(Boolean))]
  if (unique.length === 0) return new Map()
  const serviceClient = createServiceClient()
  const entries = await Promise.all(
    unique.map(async (id): Promise<[string, string]> => {
      const { data } = await serviceClient.auth.admin.getUserById(id)
      return [id, data?.user?.email || "Unknown"]
    })
  )
  return new Map(entries)
}

export async function getSales(
  businessId: string,
  branchId?: string,
  from?: string,
  to?: string
): Promise<Sale[]> {
  const client = await createServerClientForUser()

  let query = client
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

  const rows = data as any[]
  const cashierEmails = await resolveCashierEmails(rows.map((s) => s.cashier_id as string))

  return rows.map((s) => ({
    id: s.id,
    invoice_number: s.invoices?.invoice_number || "-",
    created_at: s.created_at,
    cashier_email: cashierEmails.get(s.cashier_id) || "Unknown",
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
  const client = await createServerClientForUser()
  const today = new Date()
  today.setHours(0, 0, 0, 0)

  const { data, error } = await client
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

export interface TopProduct {
  product_id: string
  product_name: string
  total_quantity: number
  total_revenue: number
}

export async function getTopProducts(
  businessId: string,
  branchId?: string,
  days = 30,
  limit = 5
): Promise<TopProduct[]> {
  const client = await createServerClientForUser()
  const since = new Date()
  since.setDate(since.getDate() - days)
  since.setHours(0, 0, 0, 0)

  let query = client
    .from("sales")
    .select(
      `sale_items(quantity, unit_price, subtotal, product_id, products(name))`
    )
    .eq("business_id", businessId)
    .gte("created_at", since.toISOString())

  if (branchId) {
    query = query.eq("branch_id", branchId)
  }

  const { data, error } = await query.limit(500)

  if (error) {
    throw new Error(error.message)
  }

  const rows = data as any[]
  const productMap = new Map<string, TopProduct>()

  for (const sale of rows) {
    for (const item of sale.sale_items as any[]) {
      const productId = item.product_id as string
      const existing =
        productMap.get(productId) || {
          product_id: productId,
          product_name: item.products?.name || "Unknown",
          total_quantity: 0,
          total_revenue: 0,
        }
      existing.total_quantity += item.quantity
      existing.total_revenue += item.subtotal || item.quantity * item.unit_price
      productMap.set(productId, existing)
    }
  }

  return Array.from(productMap.values())
    .sort((a, b) => b.total_revenue - a.total_revenue)
    .slice(0, limit)
}
