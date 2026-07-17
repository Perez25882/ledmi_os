import "server-only"
import { createServiceClient } from "@/lib/supabase/server"

export interface Shift {
  id: string
  opened_at: string
  closed_at: string | null
  opening_float: number
  expected_cash: number | null
  actual_cash: number | null
  discrepancy: number | null
  status: string
  notes: string | null
  cashier_email: string
}

export async function getShifts(businessId: string, branchId?: string): Promise<Shift[]> {
  const serviceClient = createServiceClient()

  let query = serviceClient
    .from("shifts")
    .select(
      `
      id,
      opened_at,
      closed_at,
      opening_float,
      expected_cash,
      actual_cash,
      discrepancy,
      status,
      notes,
      cashier_id
    `
    )
    .eq("business_id", businessId)
    .order("opened_at", { ascending: false })

  if (branchId) {
    query = query.eq("branch_id", branchId)
  }

  const { data, error } = await query.limit(500)

  if (error) {
    throw new Error(error.message)
  }

  return (data as any[]).map((s) => ({
    id: s.id,
    opened_at: s.opened_at,
    closed_at: s.closed_at,
    opening_float: s.opening_float,
    expected_cash: s.expected_cash,
    actual_cash: s.actual_cash,
    discrepancy: s.discrepancy,
    status: s.status,
    notes: s.notes,
    cashier_email: "-",
  }))
}
