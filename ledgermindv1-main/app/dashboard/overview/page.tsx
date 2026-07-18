import { redirect } from "next/navigation"
import { getSalesOverview } from "@/lib/supabase/data/sales"
import { requirePageAccess } from "@/lib/supabase/guards"
import { getScopedBranchFilter } from "@/lib/supabase/permissions"
import { getInventory } from "@/lib/supabase/data/inventory"
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
import { TrendingUp, Store, AlertTriangle, ArrowUpRight, Sparkles } from "lucide-react"
import { PushNotificationsButton } from "@/components/push-notifications"
import { StatCard } from "@/components/dashboard/stat-card"
import { getInsights } from "@/lib/supabase/data/insights"
import { generateProactiveInsights } from "@/lib/nvidia-ai"

export default async function OverviewPage() {
  const context = await requirePageAccess("overview")

  const { branchId: scopedBranchId } = getScopedBranchFilter(context)
  const effectiveBranchId = scopedBranchId ?? context.branchId

  const [overview, inventory, insights] = await Promise.all([
    getSalesOverview(context.businessId),
    getInventory(context.businessId, effectiveBranchId),
    getInsights(context.businessId, effectiveBranchId),
  ])

  const proactive = await generateProactiveInsights(insights)

  const lowStock = inventory.filter(
    (item) => item.status === "Low Stock" || item.status === "Out of Stock"
  )

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-foreground">
            Dashboard Overview
          </h1>
          <p className="text-muted-foreground text-sm sm:text-base">
            Today&apos;s performance across branches
          </p>
        </div>
        <PushNotificationsButton />
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <StatCard
          title="Today&apos;s Revenue"
          value={`GHS ${overview.totalRevenue.toFixed(2)}`}
          subtitle={
            <span className="inline-flex items-center text-primary">
              <ArrowUpRight className="mr-1 h-3 w-3" />
              Live sales today
            </span>
          }
          icon={TrendingUp}
        />

        <StatCard
          title="Today&apos;s Sales"
          value={overview.totalSales}
          subtitle="Transactions completed today"
          icon={Store}
        />

        <StatCard
          title="Low / Out of Stock"
          value={lowStock.length}
          subtitle="Items that need attention"
          icon={AlertTriangle}
          iconClassName="text-destructive"
          className={lowStock.length > 0 ? "border-destructive/20" : ""}
        />
      </div>

      {proactive && (
        <Card className="border-border/60 bg-gradient-to-br from-primary/5 to-transparent">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Sparkles className="h-5 w-5 text-primary" />
              Ledmi Insight
            </CardTitle>
            <CardDescription>AI-powered summary for today</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm leading-relaxed">{proactive.summary}</p>
            <div className="rounded-lg bg-muted/50 p-3 text-sm">
              <span className="font-semibold">Recommendation:</span>{" "}
              {proactive.recommendation}
            </div>
          </CardContent>
        </Card>
      )}

      <Card className="border-border/60">
        <CardHeader>
          <CardTitle>Branch Performance</CardTitle>
          <CardDescription>Revenue and sales by branch today</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead>Branch</TableHead>
                <TableHead>Sales</TableHead>
                <TableHead className="text-right">Revenue</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {overview.branchRevenue.length > 0 ? (
                overview.branchRevenue.map((branch) => (
                  <TableRow key={branch.name}>
                    <TableCell className="font-medium">{branch.name}</TableCell>
                    <TableCell>{branch.sales}</TableCell>
                    <TableCell className="text-right">
                      GHS {branch.revenue.toFixed(2)}
                    </TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={3} className="text-center py-8 text-muted-foreground">
                    No sales today.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card className="border-border/60">
        <CardHeader>
          <CardTitle>Stock Alerts</CardTitle>
          <CardDescription>
            Items that need attention in the selected branch
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {lowStock.length > 0 ? (
              lowStock.map((item) => (
                <Badge
                  key={item.id}
                  variant={item.status === "Out of Stock" ? "destructive" : "secondary"}
                  className="px-2.5 py-1"
                >
                  {item.name} ({item.quantity})
                </Badge>
              ))
            ) : (
              <p className="text-muted-foreground">All stock levels are healthy.</p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
