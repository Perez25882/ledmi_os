import "server-only"
import { createServiceClient } from "@/lib/supabase/server"
import { getCategories } from "./catalog"

export interface ProductImportRow {
  name: string
  barcode?: string
  category?: string
  price: number
  cost_price?: number
  stock_quantity?: number
  unit?: string
}

export interface ProductImportResult {
  imported: number
  skipped: number
  errors: string[]
}

export interface ResolvedCategory {
  id: string
  name: string
}

/**
 * Bulk-imports products from parsed CSV rows. For each valid row it inserts a
 * product and creates an inventory row (with the requested stock quantity) for
 * the target branch. Categories referenced by name are resolved against the
 * business's existing categories; unknown categories are skipped with an error.
 */
export async function importProducts(
  businessId: string,
  branchId: string,
  rows: ProductImportRow[]
): Promise<ProductImportResult> {
  const serviceClient = createServiceClient()

  const categories = await getCategories(businessId)
  const categoryByName = new Map<string, ResolvedCategory>(
    categories.map((c) => [c.name.toLowerCase().trim(), { id: c.id, name: c.name }])
  )

  let imported = 0
  let skipped = 0
  const errors: string[] = []

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i]

    if (!row.name || !row.name.trim()) {
      skipped++
      errors.push(`Row ${i + 2}: missing product name`)
      continue
    }
    if (Number.isNaN(row.price) || row.price < 0) {
      skipped++
      errors.push(`Row ${i + 2} ("${row.name}"): invalid price`)
      continue
    }

    let categoryId: string | null = null
    if (row.category && row.category.trim()) {
      const match = categoryByName.get(row.category.toLowerCase().trim())
      if (!match) {
        skipped++
        errors.push(`Row ${i + 2} ("${row.name}"): unknown category "${row.category}"`)
        continue
      }
      categoryId = match.id
    }

    const costPrice =
      row.cost_price !== undefined && !Number.isNaN(row.cost_price)
        ? row.cost_price
        : row.price
    const stockQty =
      row.stock_quantity !== undefined && !Number.isNaN(row.stock_quantity)
        ? Math.max(0, Math.floor(row.stock_quantity))
        : 0

    const { data: product, error: productError } = await serviceClient
      .from("products")
      .insert({
        business_id: businessId,
        name: row.name.trim(),
        sku: null,
        barcode: row.barcode?.trim() || null,
        selling_price: row.price,
        cost_price: costPrice,
        category_id: categoryId,
        reorder_threshold: 10,
      })
      .select("id")
      .single()

    if (productError || !product) {
      skipped++
      errors.push(`Row ${i + 2} ("${row.name}"): ${productError?.message || "insert failed"}`)
      continue
    }

    const { error: inventoryError } = await serviceClient
      .from("inventory")
      .upsert(
        {
          product_id: product.id,
          branch_id: branchId,
          business_id: businessId,
          quantity: stockQty,
          reorder_level: 10,
        },
        { onConflict: "product_id,branch_id" }
      )

    if (inventoryError) {
      errors.push(`Row ${i + 2} ("${row.name}"): inventory row failed — ${inventoryError.message}`)
    }

    imported++
  }

  return { imported, skipped, errors }
}
