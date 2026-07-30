"use server"

import { revalidatePath } from "next/cache"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import {
  importProducts,
  type ProductImportRow,
  type ProductImportResult,
} from "@/lib/supabase/data/product-import"

async function verifyCatalogAccess() {
  const context = await getCurrentUserRoleContext()
  if (!context) throw new Error("Unauthorized")
  if (context.roleName === "cashier") throw new Error("Forbidden")
  if (!canAccessPage(context.roleName, "catalog")) throw new Error("Forbidden")
  return context
}

export async function importProductsAction(
  rows: ProductImportRow[]
): Promise<ProductImportResult> {
  const context = await verifyCatalogAccess()
  const result = await importProducts(context.businessId, context.branchId, rows)
  revalidatePath("/dashboard/catalog")
  revalidatePath("/dashboard/inventory/supabase")
  return result
}
