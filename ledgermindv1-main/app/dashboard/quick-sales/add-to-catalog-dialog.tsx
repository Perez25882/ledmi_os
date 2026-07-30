"use client"

import { useState } from "react"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { addQuickSaleToCatalogAction } from "./actions"
import type { QuickSaleGroup } from "@/lib/supabase/data/quick-sales"

interface Category {
  id: string
  name: string
}

interface AddToCatalogDialogProps {
  item: QuickSaleGroup
  categories: Category[]
  branchId: string
}

export function AddToCatalogDialog({
  item,
  categories,
  branchId,
}: AddToCatalogDialogProps) {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState(item.quick_sale_name)
  const [categoryId, setCategoryId] = useState<string>("")
  const [price, setPrice] = useState<string>(item.avg_price.toFixed(2))
  const [barcode, setBarcode] = useState("")
  const [saving, setSaving] = useState(false)

  async function handleConfirm() {
    setSaving(true)
    try {
      await addQuickSaleToCatalogAction({
        quickSaleName: item.quick_sale_name,
        name: name.trim(),
        categoryId: categoryId || undefined,
        price: parseFloat(price),
        barcode: barcode.trim() || undefined,
        branchId,
      })
      toast.success(`Added "${name.trim()}" to the catalog`)
      setOpen(false)
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to add to catalog")
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">
          Add to Catalog
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add to Catalog</DialogTitle>
          <DialogDescription>
            Promote this quick-sale item to a catalog product. It will be added
            with 0 starting stock for the current branch.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="qs-name">Product name</Label>
            <Input
              id="qs-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="qs-category">Category</Label>
            <Select value={categoryId} onValueChange={setCategoryId}>
              <SelectTrigger id="qs-category" className="w-full">
                <SelectValue placeholder="No category" />
              </SelectTrigger>
              <SelectContent>
                {categories.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="qs-price">Price (GHS)</Label>
            <Input
              id="qs-price"
              type="number"
              step="0.01"
              min="0"
              value={price}
              onChange={(e) => setPrice(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Pre-filled with the average price it was sold at.
            </p>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="qs-barcode">Barcode (optional)</Label>
            <Input
              id="qs-barcode"
              value={barcode}
              onChange={(e) => setBarcode(e.target.value)}
              placeholder="Scan or enter a barcode"
            />
          </div>
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={saving}
          >
            Cancel
          </Button>
          <Button onClick={handleConfirm} disabled={saving || !name.trim()}>
            {saving ? "Adding..." : "Add to Catalog"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
