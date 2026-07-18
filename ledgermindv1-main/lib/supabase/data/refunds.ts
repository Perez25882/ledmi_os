import "server-only"
import { createServerClientForUser } from "@/lib/supabase/server"

export interface RefundableItem {
  id: string
  product_id: string
  product_name: string
  quantity: number
  unit_price: number
  refunded_quantity: number
}

export async function getSaleItemsForRefund(businessId: string, saleId: string): Promise<RefundableItem[]> {
  const client = await createServerClientForUser()

  const { data, error } = await client
    .from("sale_items")
    .select(
      `
      id,
      product_id,
      quantity,
      unit_price,
      products(name)
    `
    )
    .eq("sale_id", saleId)

  if (error) {
    throw new Error(error.message)
  }

  const { data: refundsData, error: refundsError } = await client
    .from("refund_items")
    .select("sale_item_id, quantity, refunds!inner(sale_id, status)")
    .eq("refunds.sale_id", saleId)
    .eq("refunds.status", "completed")

  if (refundsError) {
    throw new Error(refundsError.message)
  }

  const refunded = new Map<string, number>()
  for (const row of (refundsData as any[]) ?? []) {
    const id = row.sale_item_id as string
    refunded.set(id, (refunded.get(id) || 0) + (row.quantity as number))
  }

  return (data as any[]).map((item) => ({
    id: item.id,
    product_id: item.product_id,
    product_name: item.products?.name || "Unknown",
    quantity: item.quantity,
    unit_price: item.unit_price,
    refunded_quantity: refunded.get(item.id) || 0,
  }))
}

export interface RefundInput {
  saleId: string
  reason?: string
  items: Array<{ saleItemId: string; quantity: number }>
}

export async function createRefund(businessId: string, branchId: string, cashierId: string, input: RefundInput) {
  const client = await createServerClientForUser()

  const itemsJson = input.items.map((item) => ({
    sale_item_id: item.saleItemId,
    quantity: item.quantity,
  }))

  const { data, error } = await client.rpc("process_refund", {
    p_business_id: businessId,
    p_branch_id: branchId,
    p_cashier_id: cashierId,
    p_sale_id: input.saleId,
    p_items: itemsJson,
    p_reason: input.reason || null,
  })

  if (error) {
    throw new Error(error.message)
  }

  return data as string
}

export interface RefundListItem {
  id: string
  created_at: string
  total_amount: number
  reason: string | null
  status: string
  sale_id: string
  invoice_number: string | null
}

export async function getRefunds(businessId: string, branchId?: string): Promise<RefundListItem[]> {
  const client = await createServerClientForUser()

  let query = client
    .from("refunds")
    .select(
      `
      id,
      created_at,
      total_amount,
      reason,
      status,
      sale_id,
      sales(invoices(invoice_number))
    `
    )
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })

  if (branchId) {
    query = query.eq("branch_id", branchId)
  }

  const { data, error } = await query.limit(500)

  if (error) {
    throw new Error(error.message)
  }

  return (data as any[]).map((r) => ({
    id: r.id,
    created_at: r.created_at,
    total_amount: r.total_amount,
    reason: r.reason,
    status: r.status,
    sale_id: r.sale_id,
    invoice_number: r.sales?.invoices?.invoice_number || null,
  }))
}
