"use server"

import { revalidatePath } from "next/cache"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { createRefund, getSaleItemsForRefund, type RefundInput } from "@/lib/supabase/data/refunds"
import { canAccessPage } from "@/lib/supabase/permissions"

export async function getSaleItemsForRefundAction(saleId: string) {
  const context = await getCurrentUserRoleContext()
  if (!context) throw new Error("Unauthorized")
  if (!canAccessPage(context.roleName, "sales")) throw new Error("Forbidden")

  return getSaleItemsForRefund(context.businessId, saleId)
}

export async function createRefundAction(input: RefundInput) {
  const context = await getCurrentUserRoleContext()
  if (!context) throw new Error("Unauthorized")
  if (!canAccessPage(context.roleName, "sales")) throw new Error("Forbidden")

  await createRefund(context.businessId, context.branchId, context.userId, input)
  revalidatePath("/dashboard/refunds")
}
