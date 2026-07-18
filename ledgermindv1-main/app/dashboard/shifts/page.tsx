import { redirect } from "next/navigation"
import { requirePageAccess } from "@/lib/supabase/guards"
import { getScopedBranchFilter } from "@/lib/supabase/permissions"
import { getShifts } from "@/lib/supabase/data/shifts"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"

export default async function ShiftsPage() {
  const context = await requirePageAccess("shifts")

  const { branchId: scopedBranchId } = getScopedBranchFilter(context)
  const effectiveBranchId = scopedBranchId ?? context.branchId

  const shifts = await getShifts(context.businessId, effectiveBranchId)

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
