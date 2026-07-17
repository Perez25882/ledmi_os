import { redirect } from "next/navigation"
import { createServerClientForUser } from "@/lib/supabase/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import { getShifts } from "@/lib/supabase/data/shifts"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"

export default async function ShiftsPage() {
  const userClient = await createServerClientForUser()
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser()

  if (userError || !user) {
    redirect("/auth/login")
  }

  const context = await getCurrentUserRoleContext()
  if (!context) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold">Shifts</h1>
        <p className="text-muted-foreground">No business context found.</p>
      </div>
    )
  }

  if (!canAccessPage(context.roleName, "sales")) {
    redirect("/dashboard/overview")
  }

  const shifts = await getShifts(context.businessId, context.branchId)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Shift Ledger</h1>
        <p className="text-muted-foreground text-sm sm:text-base">Cashier shift history and reconciliation</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Shifts</CardTitle>
          <CardDescription>{shifts.length} shifts</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Cashier</TableHead>
                <TableHead>Opened</TableHead>
                <TableHead>Closed</TableHead>
                <TableHead>Float</TableHead>
                <TableHead>Expected</TableHead>
                <TableHead>Actual</TableHead>
                <TableHead>Discrepancy</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {shifts.length > 0 ? (
                shifts.map((shift) => (
                  <TableRow key={shift.id}>
                    <TableCell>{shift.cashier_email}</TableCell>
                    <TableCell>{new Date(shift.opened_at).toLocaleString()}</TableCell>
                    <TableCell>
                      {shift.closed_at ? new Date(shift.closed_at).toLocaleString() : "-"}
                    </TableCell>
                    <TableCell>GHS {shift.opening_float.toFixed(2)}</TableCell>
                    <TableCell>
                      {shift.expected_cash != null ? `GHS ${shift.expected_cash.toFixed(2)}` : "-"}
                    </TableCell>
                    <TableCell>
                      {shift.actual_cash != null ? `GHS ${shift.actual_cash.toFixed(2)}` : "-"}
                    </TableCell>
                    <TableCell
                      className={
                        shift.discrepancy && shift.discrepancy !== 0
                          ? "text-destructive font-medium"
                          : ""
                      }
                    >
                      {shift.discrepancy != null ? `GHS ${shift.discrepancy.toFixed(2)}` : "-"}
                    </TableCell>
                    <TableCell>
                      <Badge variant={shift.status === "open" ? "secondary" : "default"}>
                        {shift.status}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={8} className="text-center py-8">
                    No shifts recorded yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
