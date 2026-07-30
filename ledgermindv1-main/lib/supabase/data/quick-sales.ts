import "server-only"
import { createServerClientForUser, createServiceClient } from "@/lib/supabase/server"
import { getCategories } from "./catalog"

export interface QuickSaleGroup {
  quick_sale_name: string
  times_sold: number
  total_revenue: number
  avg_price: number
  last_sold: string
}

/**
 * Fetches all quick-sale line items for a business (optionally scoped to a
 * branch), joined with sales for the timestamp, then grouped by
 * `quick_sale_name`. Results are sorted by times sold descending.
 */
export async function getQuickSales(
  businessId: string,
  branchId?: string
): Promise<QuickSaleGroup[]> {
  const client = await createServerClientForUser()

  let query = client
    .from("sale_items")
    .select(
      `
      quick_sale_name,
      quantity,
      unit_price,
      subtotal,
      sales!inner(created_at, branch_id, business_id)
    `
    )
    .eq("is_quick_sale", true)
    .not("quick_sale_name", "is", null)
    .eq("sales.business_id", businessId)

  if (branchId) {
    query = query.eq("sales.branch_id", branchId)
  }

  const { data, error } = await query.limit(2000)

  if (error) {
    throw new Error(error.message)
  }

  const rows = (data as any[]) ?? []
  const groups = new Map<string, QuickSaleGroup>()

  for (const row of rows) {
    const name = (row.quick_sale_name as string) || "Unknown"
    const sale = row.sales as any
    const createdAt = (sale?.created_at as string) || ""
    const subtotal = Number(
      row.subtotal != null ? row.subtotal : row.quantity * row.unit_price
    )
    const unitPrice = Number(row.unit_price ?? 0)

    const existing =
      groups.get(name) ??
      {
        quick_sale_name: name,
        times_sold: 0,
        total_revenue: 0,
        avg_price: 0,
        last_sold: createdAt,
      }

    existing.times_sold += 1
    existing.total_revenue += subtotal
    existing.avg_price += unitPrice
    if (createdAt && (!existing.last_sold || createdAt > existing.last_sold)) {
      existing.last_sold = createdAt
    }
    groups.set(name, existing)
  }

  return Array.from(groups.values())
    .map((g) => ({
      ...g,
      avg_price: g.times_sold > 0 ? g.avg_price / g.times_sold : 0,
    }))
    .sort((a, b) => b.times_sold - a.times_sold)
}

export interface QuickSaleToCatalogInput {
  quickSaleName: string
  name: string
  categoryId?: string
  price: number
  barcode?: string
  branchId: string
}

/**
 * Promotes a quick-sale item into the catalog: inserts a product and creates
 * an inventory row (starting at 0 stock) for the target branch. Returns the
 * new product id.
 */
export async function addQuickSaleToCatalog(
  businessId: string,
  input: QuickSaleToCatalogInput
): Promise<string> {
  const serviceClient = createServiceClient()

  const { data: product, error: productError } = await serviceClient
    .from("products")
    .insert({
      business_id: businessId,
      name: input.name,
      sku: null,
      barcode: input.barcode || null,
      selling_price: input.price,
      cost_price: input.price,
      category_id: input.categoryId || null,
      reorder_threshold: 10,
    })
    .select("id")
    .single()

  if (productError || !product) {
    throw new Error(productError?.message || "Failed to create product")
  }

  const productId = product.id as string

  const { error: inventoryError } = await serviceClient
    .from("inventory")
    .upsert(
      {
        product_id: productId,
        branch_id: input.branchId,
        business_id: businessId,
        quantity: 0,
        reorder_level: 10,
      },
      { onConflict: "product_id,branch_id" }
    )

  if (inventoryError) {
    throw new Error(inventoryError.message)
  }

  return productId
}

export { getCategories }
