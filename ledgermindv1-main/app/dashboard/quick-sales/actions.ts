"use server"

import { revalidatePath } from "next/cache"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import {
  addQuickSaleToCatalog,
  type QuickSaleToCatalogInput,
} from "@/lib/supabase/data/quick-sales"

async function verifyQuickSalesAccess() {
  const context = await getCurrentUserRoleContext()
  if (!context) throw new Error("Unauthorized")
  if (context.roleName === "cashier") throw new Error("Forbidden")
  if (!canAccessPage(context.roleName, "quick-sales")) throw new Error("Forbidden")
  return context
}

export async function addQuickSaleToCatalogAction(input: QuickSaleToCatalogInput) {
  const context = await verifyQuickSalesAccess()
  const productId = await addQuickSaleToCatalog(context.businessId, input)
  revalidatePath("/dashboard/quick-sales")
  revalidatePath("/dashboard/catalog")
  return { productId }
}
