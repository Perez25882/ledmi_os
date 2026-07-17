"use server"

import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import { getSales } from "@/lib/supabase/data/sales"

export async function exportSalesCsv(from?: string, to?: string) {
  const context = await getCurrentUserRoleContext()
  if (!context) throw new Error("Unauthorized")
  if (!canAccessPage(context.roleName, "sales")) throw new Error("Forbidden")

  const sales = await getSales(context.businessId, context.branchId, from, to)

  const rows = [
    ["Invoice", "Date", "Cashier", "Method", "Total", "Items"],
    ...sales.map((sale) => [
      sale.invoice_number,
      new Date(sale.created_at).toISOString(),
      sale.cashier_email,
      sale.payment_method,
      sale.total.toFixed(2),
      sale.items.length.toString(),
    ]),
  ]

  const csv = rows.map((row) => row.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(",")).join("\n")
  return csv
}
