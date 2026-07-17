import "server-only"
import { createServiceClient } from "@/lib/supabase/server"

export interface BusinessContext {
  businessId: string
  branchId: string
  branches: Array<{ id: string; name: string }>
}

export async function getBusinessContext(userId: string): Promise<BusinessContext | null> {
  const serviceClient = createServiceClient()

  const { data: roles, error } = await serviceClient
    .from("user_business_roles")
    .select("business_id, businesses(id, name)")
    .eq("user_id", userId)

  if (error || !roles || roles.length === 0) {
    return null
  }

  const primary = roles[0] as any
  const businessId = primary.business_id as string

  const { data: branches, error: branchesError } = await serviceClient
    .from("branches")
    .select("id, name")
    .eq("business_id", businessId)
    .is("deleted_at", null)
    .order("created_at", { ascending: true })

  if (branchesError || !branches || branches.length === 0) {
    return null
  }

  const branchId = branches[0].id

  return {
    businessId,
    branchId,
    branches: branches as Array<{ id: string; name: string }>,
  }
}

export interface InventoryItem {
  id: string
  name: string
  sku: string | null
  barcode: string | null
  category_name: string | null
  unit_price: number
  cost_price: number
  quantity: number
  reorder_level: number
  value: number
  status: "In Stock" | "Low Stock" | "Out of Stock"
}

export async function getInventory(
  businessId: string,
  branchId: string
): Promise<InventoryItem[]> {
  const serviceClient = createServiceClient()

  const { data, error } = await serviceClient
    .from("products")
    .select(
      `
      id,
      name,
      sku,
      barcode,
      selling_price,
      cost_price,
      categories(name),
      inventory!inner(quantity, reorder_level)
    `
    )
    .eq("business_id", businessId)
    .eq("inventory.branch_id", branchId)
    .is("deleted_at", null)
    .order("name")

  if (error || !data) {
    throw new Error(error?.message || "Failed to load inventory")
  }

  return (data as any[]).map((p) => {
    const quantity = Number(p.inventory?.[0]?.quantity ?? 0)
    const reorderLevel = Number(p.inventory?.[0]?.reorder_level ?? 0)
    const unitPrice = Number(p.selling_price ?? 0)
    const status: InventoryItem["status"] =
      quantity === 0 ? "Out of Stock" : quantity <= reorderLevel ? "Low Stock" : "In Stock"

    return {
      id: p.id as string,
      name: p.name as string,
      sku: (p.sku as string) || null,
      barcode: (p.barcode as string) || null,
      category_name: p.categories?.name ?? null,
      unit_price: unitPrice,
      cost_price: Number(p.cost_price ?? 0),
      quantity,
      reorder_level: reorderLevel,
      value: quantity * unitPrice,
      status,
    }
  })
}

export async function getCategories(businessId: string) {
  const serviceClient = createServiceClient()

  const { data, error } = await serviceClient
    .from("categories")
    .select("id, name")
    .eq("business_id", businessId)
    .order("name")

  if (error) {
    throw new Error(error.message)
  }

  return (data ?? []) as Array<{ id: string; name: string }>
}
