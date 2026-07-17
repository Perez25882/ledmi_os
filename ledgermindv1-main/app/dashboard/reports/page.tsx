import { redirect } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { SimpleBarChart, SimplePieChart } from "@/components/ui/simple-charts"
import {
  DollarSign,
  TrendingUp,
  ShoppingCart,
  Package,
  AlertTriangle,
} from "lucide-react"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { getSalesOverview } from "@/lib/supabase/data/sales"
import { getInventory } from "@/lib/supabase/data/inventory"
import { getCategories } from "@/lib/supabase/data/catalog"

export default async function ReportsPage() {
  const context = await getCurrentUserRoleContext()
  if (!context) {
    redirect("/onboarding")
  }

  const [overview, inventory, categories] = await Promise.all([
    getSalesOverview(context.businessId),
    getInventory(context.businessId, context.branchId),
    getCategories(context.businessId),
  ])

  const totalRevenue = overview.totalRevenue
  const totalSales = overview.totalSales
  const avgOrderValue = totalSales > 0 ? totalRevenue / totalSales : 0
  const lowStock = inventory.filter((i) => i.status === "Low Stock" || i.status === "Out of Stock").length
  const totalInventoryValue = inventory.reduce((sum, i) => sum + i.value, 0)
  const totalCostValue = inventory.reduce((sum, i) => sum + i.quantity * i.cost_price, 0)
  const grossProfit = totalRevenue - totalCostValue * 0.6
  const profitMargin = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0

  const categoryMap = new Map(categories.map((c) => [c.id, c.name]))
  const categoryData = inventory.reduce(
    (acc: Array<{ name: string; value: number; color: string }>, item) => {
      const catName = item.category_name || "Uncategorized"
      const existing = acc.find((c) => c.name === catName)
      if (existing) {
        existing.value += item.quantity
      } else {
        acc.push({
          name: catName,
          value: item.quantity,
          color: `hsl(var(--chart-${acc.length + 1}))`,
        })
      }
      return acc
    },
    []
  )

  const monthlySalesData = Array.from({ length: 6 }, (_, i) => {
    const date = new Date()
    date.setMonth(date.getMonth() - (5 - i))
    const monthName = date.toLocaleDateString("en", { month: "short" })
    return { month: monthName, sales: 0, profit: 0 }
  })

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Reports & Analytics</h1>
        <p className="text-muted-foreground">Business performance and inventory insights</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Revenue</CardTitle>
            <DollarSign className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">${totalRevenue.toLocaleString()}</div>
            <p className="text-xs text-muted-foreground">Today</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Inventory Value</CardTitle>
            <Package className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">${totalInventoryValue.toLocaleString()}</div>
            <p className="text-xs text-muted-foreground">{inventory.length} items</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Avg Order Value</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">${avgOrderValue.toFixed(2)}</div>
            <p className="text-xs text-muted-foreground">{totalSales} orders</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Low Stock</CardTitle>
            <AlertTriangle className="h-4 w-4 text-destructive" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-destructive">{lowStock}</div>
            <p className="text-xs text-muted-foreground">Items need attention</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        <Card className="min-h-[400px]">
          <CardHeader>
            <CardTitle>Revenue Trend</CardTitle>
            <CardDescription>Monthly revenue and estimated profit</CardDescription>
          </CardHeader>
          <CardContent className="h-[320px]">
            <SimpleBarChart data={monthlySalesData} className="h-full w-full" />
          </CardContent>
        </Card>

        <Card className="min-h-[400px]">
          <CardHeader>
            <CardTitle>Category Distribution</CardTitle>
            <CardDescription>Inventory units by category</CardDescription>
          </CardHeader>
          <CardContent className="h-[320px]">
            <SimplePieChart data={categoryData} className="h-full w-full" />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Performance Summary</CardTitle>
          <CardDescription>Key business metrics at a glance</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="text-center p-4 bg-muted/50 rounded-lg">
              <div className="text-2xl font-bold">{profitMargin.toFixed(1)}%</div>
              <div className="text-xs text-muted-foreground">Est. Profit Margin</div>
            </div>
            <div className="text-center p-4 bg-muted/50 rounded-lg">
              <div className="text-2xl font-bold">{inventory.length}</div>
              <div className="text-xs text-muted-foreground">Total Products</div>
            </div>
            <div className="text-center p-4 bg-muted/50 rounded-lg">
              <div className="text-2xl font-bold">{categories.length}</div>
              <div className="text-xs text-muted-foreground">Categories</div>
            </div>
            <div className="text-center p-4 bg-muted/50 rounded-lg">
              <div className="text-2xl font-bold">{overview.branchRevenue.length}</div>
              <div className="text-xs text-muted-foreground">Active Branches</div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
