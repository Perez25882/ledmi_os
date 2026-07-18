import { redirect } from "next/navigation"
import { getInventory, getCategories } from "@/lib/supabase/data/inventory"
import { requirePageAccess } from "@/lib/supabase/guards"
import { getScopedBranchFilter } from "@/lib/supabase/permissions"
import { InventoryRealtime } from "./realtime"
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
import { Package, AlertTriangle } from "lucide-react"
import Link from "next/link"

export default async function SupabaseInventoryPage() {
  const context = await requirePageAccess("inventory")

  const { branchId: scopedBranchId } = getScopedBranchFilter(context)
  const effectiveBranchId = scopedBranchId ?? context.branchId

  const [items, categories] = await Promise.all([
    getInventory(context.businessId, effectiveBranchId),
    getCategories(context.businessId),
  ])

  const totalItems = items.length
  const lowStockItems = items.filter((item) => item.status === "Low Stock").length
  const outOfStockItems = items.filter((item) => item.status === "Out of Stock").length
  const totalValue = items.reduce((sum, item) => sum + item.value, 0)

  return (
    <div className="space-y-6">
      <InventoryRealtime branchId={context.branchId} />
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Inventory (Supabase)</h1>
          <p className="text-muted-foreground text-sm sm:text-base">
            Live stock for your selected branch
          </p>
        </div>
        {context.branches.length > 1 && (
          <div className="text-sm text-muted-foreground">
            Branch: {context.branches.find((b) => b.id === context.branchId)?.name ?? context.branchId}
          </div>
        )}
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Products</CardTitle>
            <Package className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totalItems}</div>
            <p className="text-xs text-muted-foreground">Products in inventory</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Low / Out of Stock</CardTitle>
            <AlertTriangle className="h-4 w-4 text-destructive" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-destructive">
              {lowStockItems + outOfStockItems}
            </div>
            <p className="text-xs text-muted-foreground">Items need attention</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Value</CardTitle>
            <Package className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">GHS {totalValue.toFixed(2)}</div>
            <p className="text-xs text-muted-foreground">Current inventory value</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Inventory Items</CardTitle>
          <CardDescription>
            {categories.length} categories · {items.length} products
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto -mx-4 sm:mx-0">
            <div className="min-w-[800px] sm:min-w-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Item</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>SKU</TableHead>
                    <TableHead>Stock</TableHead>
                    <TableHead>Reorder Level</TableHead>
                    <TableHead>Unit Price</TableHead>
                    <TableHead>Value</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {items.length > 0 ? (
                    items.map((item) => (
                      <TableRow key={item.id}>
                        <TableCell>
                          <div>
                            <div className="font-medium">{item.name}</div>
                            {item.barcode && (
                              <div className="text-xs text-muted-foreground">{item.barcode}</div>
                            )}
                          </div>
                        </TableCell>
                        <TableCell>
                          {item.category_name ? (
                            <Badge variant="secondary">{item.category_name}</Badge>
                          ) : (
                            <span className="text-muted-foreground">-</span>
                          )}
                        </TableCell>
                        <TableCell>
                          <code className="text-xs bg-muted px-1 py-0.5 rounded">
                            {item.sku || "-"}
                          </code>
                        </TableCell>
                        <TableCell>
                          <span className={item.status !== "In Stock" ? "text-destructive font-medium" : ""}>
                            {item.quantity}
                          </span>
                        </TableCell>
                        <TableCell>{item.reorder_level}</TableCell>
                        <TableCell>GHS {item.unit_price.toFixed(2)}</TableCell>
                        <TableCell>GHS {item.value.toFixed(2)}</TableCell>
                        <TableCell>
                          {item.status === "Low Stock" ? (
                            <Badge variant="destructive">Low Stock</Badge>
                          ) : item.status === "Out of Stock" ? (
                            <Badge variant="destructive">Out of Stock</Badge>
                          ) : (
                            <Badge variant="secondary">In Stock</Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ))
                  ) : (
                    <TableRow>
                      <TableCell colSpan={8} className="text-center py-8">
                        <div className="flex flex-col items-center gap-2">
                          <Package className="h-12 w-12 text-muted-foreground" />
                          <p className="text-muted-foreground">No inventory items found</p>
                          <p className="text-sm text-muted-foreground">
                            Add products via the dashboard or use the demo seed API.
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
