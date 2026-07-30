import { requirePageAccess } from "@/lib/supabase/guards"
import { getScopedBranchFilter } from "@/lib/supabase/permissions"
import { getSelectedBranchId } from "@/lib/supabase/selected-branch"
import { getQuickSales } from "@/lib/supabase/data/quick-sales"
import { getCategories } from "@/lib/supabase/data/catalog"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Zap } from "lucide-react"
import { AddToCatalogDialog } from "./add-to-catalog-dialog"

function formatDate(iso: string): string {
  if (!iso) return "-"
  const d = new Date(iso)
  return d.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  })
}

export default async function QuickSalesPage() {
  const context = await requirePageAccess("quick-sales")

  const selectedBranchId = await getSelectedBranchId(context)
  const { branchId: scopedBranchId, allBranches } = getScopedBranchFilter(
    context,
    selectedBranchId
  )
  const effectiveBranchId = allBranches ? undefined : scopedBranchId
  const targetBranchId = scopedBranchId ?? context.branchId

  const [groups, categories] = await Promise.all([
    getQuickSales(context.businessId, effectiveBranchId),
    getCategories(context.businessId),
  ])

  const totalRevenue = groups.reduce((sum, g) => sum + g.total_revenue, 0)
  const totalSold = groups.reduce((sum, g) => sum + g.times_sold, 0)

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold text-foreground">
            Quick Sales Review
          </h1>
          <p className="text-muted-foreground text-sm sm:text-base">
            Ad-hoc items sold by cashiers. Promote recurring ones to your catalog.
          </p>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Quick-Sale Items</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{groups.length}</div>
            <p className="text-xs text-muted-foreground">Distinct names sold</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Times Sold</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totalSold}</div>
            <p className="text-xs text-muted-foreground">Total line items</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Revenue</CardTitle>
            <Zap className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">GHS {totalRevenue.toFixed(2)}</div>
            <p className="text-xs text-muted-foreground">From quick sales</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Quick-Sale Items</CardTitle>
          <CardDescription>
            Sorted by times sold (most frequent first)
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto -mx-4 sm:mx-0">
            <div className="min-w-[800px] sm:min-w-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Quick Sale Item Name</TableHead>
                    <TableHead className="text-right">Times Sold</TableHead>
                    <TableHead className="text-right">Total Revenue</TableHead>
                    <TableHead>Last Sold</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {groups.length > 0 ? (
                    groups.map((item) => (
                      <TableRow key={item.quick_sale_name}>
                        <TableCell className="font-medium">
                          {item.quick_sale_name}
                        </TableCell>
                        <TableCell className="text-right">
                          <Badge variant="secondary">{item.times_sold}</Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          GHS {item.total_revenue.toFixed(2)}
                        </TableCell>
                        <TableCell>{formatDate(item.last_sold)}</TableCell>
                        <TableCell className="text-right">
                          <AddToCatalogDialog
                            item={item}
                            categories={categories}
                            branchId={targetBranchId}
                          />
                        </TableCell>
                      </TableRow>
                    ))
                  ) : (
                    <TableRow>
                      <TableCell colSpan={5} className="text-center py-8">
                        <div className="flex flex-col items-center gap-2">
                          <Zap className="h-12 w-12 text-muted-foreground" />
                          <p className="text-muted-foreground">
                            No quick sales recorded yet
                          </p>
                          <p className="text-sm text-muted-foreground">
                            Cashiers can sell ad-hoc items from the POS — they
                            will appear here for review.
                          </p>
                        </div>
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
