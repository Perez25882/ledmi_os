"use server"

import { revalidatePath } from "next/cache"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { createRefund, getSaleItemsForRefund, type RefundInput } from "@/lib/supabase/data/refunds"
import { canAccessPage } from "@/lib/supabase/permissions"

async function verifyRefundAccess() {
  const context = await getCurrentUserRoleContext()
  if (!context) throw new Error("Unauthorized")
  if (context.roleName === "cashier") throw new Error("Forbidden")
  if (!canAccessPage(context.roleName, "refunds")) throw new Error("Forbidden")
  return context
}

export async function getSaleItemsForRefundAction(saleId: string) {
  const context = await verifyRefundAccess()
  return getSaleItemsForRefund(context.businessId, saleId)
}

export async function createRefundAction(input: RefundInput) {
  const context = await verifyRefundAccess()
  await createRefund(context.businessId, context.branchId, context.userId, input)
  revalidatePath("/dashboard/refunds")
}
