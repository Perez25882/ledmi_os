import { requirePageAccess } from "@/lib/supabase/guards"
import { getProducts, getCategories } from "@/lib/supabase/data/catalog"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  createProductAction,
  createCategoryAction,
  deleteProductAction,
  deleteCategoryAction,
} from "./actions"
import { DeleteButton } from "./delete-button"
import { Package, Tag, Upload } from "lucide-react"
import Link from "next/link"

export default async function CatalogPage() {
  const context = await requirePageAccess("catalog")

  const [products, categories] = await Promise.all([
    getProducts(context.businessId),
    getCategories(context.businessId),
  ])

  const categoryOptions = categories.map((c) => (
    <option key={c.id} value={c.id}>
      {c.name}
    </option>
  ))

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Catalog</h1>
          <p className="text-muted-foreground text-sm sm:text-base">
            Manage products and categories
          </p>
        </div>
        <Button asChild variant="outline">
          <Link href="/dashboard/catalog/import">
            <Upload className="h-4 w-4" />
            Import CSV
          </Link>
        </Button>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Tag className="h-4 w-4" /> Add Category
            </CardTitle>
          </CardHeader>
          <CardContent>
            <form action={createCategoryAction} className="flex gap-2">
              <Input name="name" placeholder="Category name" required />
              <Button type="submit">Add</Button>
            </form>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Package className="h-4 w-4" /> Add Product
            </CardTitle>
          </CardHeader>
          <CardContent>
            <form action={createProductAction} className="grid gap-2">
              <Input name="name" placeholder="Product name" required />
              <div className="grid grid-cols-2 gap-2">
                <Input name="sku" placeholder="SKU" />
                <Input name="barcode" placeholder="Barcode" />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <Input
                  name="sellingPrice"
                  placeholder="Selling price"
                  type="number"
                  step="0.01"
                  required
                />
                <Input
                  name="costPrice"
                  placeholder="Cost price"
                  type="number"
                  step="0.01"
                  required
                />
              </div>
              <select
                name="categoryId"
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              >
                <option value="">No category</option>
                {categoryOptions}
              </select>
              <Input
                name="reorderThreshold"
                placeholder="Reorder threshold"
                type="number"
                defaultValue="10"
              />
              <Button type="submit">Add Product</Button>
            </form>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Categories</CardTitle>
          <CardDescription>{categories.length} categories</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {categories.map((category) => (
              <Badge key={category.id} variant="secondary" className="gap-2">
                {category.name}
                <DeleteButton action={() => deleteCategoryAction(category.id)} label="×" />
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Products</CardTitle>
          <CardDescription>{products.length} products</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto -mx-4 sm:mx-0">
            <div className="min-w-[800px] sm:min-w-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>SKU</TableHead>
                    <TableHead>Barcode</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>Price</TableHead>
                    <TableHead>Cost</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {products.length > 0 ? (
                    products.map((product) => (
                      <TableRow key={product.id}>
                        <TableCell className="font-medium">{product.name}</TableCell>
                        <TableCell>{product.sku || "-"}</TableCell>
                        <TableCell>{product.barcode || "-"}</TableCell>
                        <TableCell>
                          {product.category_name ? (
                            <Badge variant="secondary">{product.category_name}</Badge>
                          ) : (
                            "-"
                          )}
                        </TableCell>
                        <TableCell>GHS {product.selling_price.toFixed(2)}</TableCell>
                        <TableCell>GHS {product.cost_price.toFixed(2)}</TableCell>
                        <TableCell className="text-right">
                          <DeleteButton action={() => deleteProductAction(product.id)} />
                        </TableCell>
                      </TableRow>
                    ))
                  ) : (
                    <TableRow>
                      <TableCell colSpan={7} className="text-center py-8">
                        No products yet.
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
