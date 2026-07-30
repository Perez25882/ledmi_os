import { getSales } from "@/lib/supabase/data/sales"
import { requirePageAccess } from "@/lib/supabase/guards"
import { getScopedBranchFilter } from "@/lib/supabase/permissions"
import { getSelectedBranchId } from "@/lib/supabase/selected-branch"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Receipt } from "lucide-react"
import { SalesFilter } from "./filter"
import { ExportSalesButton } from "./export-button"
import { SalesTable } from "./sales-table"

export default async function SalesPage({
  searchParams,
}: {
  searchParams?: { branch?: string; from?: string; to?: string }
}) {
  const context = await requirePageAccess("sales")

  const selectedBranchId = await getSelectedBranchId(context)
  const { branchId: scopedBranchId, allBranches } = getScopedBranchFilter(
    context,
    selectedBranchId
  )
  const requestedBranch = allBranches ? searchParams?.branch : scopedBranchId
  const effectiveBranchId = allBranches ? requestedBranch : scopedBranchId

  const sales = await getSales(
    context.businessId,
    effectiveBranchId,
    searchParams?.from,
    searchParams?.to
  )

  const totalRevenue = sales.reduce((sum, sale) => sum + sale.total, 0)

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Sales Ledger</h1>
          <p className="text-muted-foreground text-sm sm:text-base">
            Finalized sales across all branches
          </p>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Sales</CardTitle>
            <Receipt className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{sales.length}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Revenue</CardTitle>
            <Receipt className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">GHS {totalRevenue.toFixed(2)}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div>
              <CardTitle>Transactions</CardTitle>
              <CardDescription>Showing up to 500 most recent sales</CardDescription>
            </div>
            <div className="flex flex-col sm:flex-row gap-2">
              <SalesFilter />
              <ExportSalesButton from={searchParams?.from} to={searchParams?.to} />
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto -mx-4 sm:mx-0">
            <div className="min-w-[900px] sm:min-w-0">
              <SalesTable sales={sales} />
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
