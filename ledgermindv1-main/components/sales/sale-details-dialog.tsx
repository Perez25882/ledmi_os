"use client"

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import type { Sale } from "@/lib/supabase/data/sales"

interface SaleDetailsDialogProps {
  sale: Sale | null
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function SaleDetailsDialog({
  sale,
  open,
  onOpenChange,
}: SaleDetailsDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Sale Details</DialogTitle>
          <DialogDescription>
            {sale
              ? `Invoice ${sale.invoice_number}`
              : "Complete sale information"}
          </DialogDescription>
        </DialogHeader>

        {sale && (
          <div className="space-y-6">
            {/* Sale Information */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Sale Information</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-sm font-medium text-muted-foreground">
                      Invoice
                    </p>
                    <p className="text-sm font-medium">{sale.invoice_number}</p>
                  </div>
                  <div>
                    <p className="text-sm font-medium text-muted-foreground">
                      Payment Method
                    </p>
                    <Badge
                      variant={
                        sale.payment_method === "cash" ? "secondary" : "outline"
                      }
                      className="capitalize"
                    >
                      {sale.payment_method}
                    </Badge>
                  </div>
                  <div>
                    <p className="text-sm font-medium text-muted-foreground">
                      Date
                    </p>
                    <p className="text-sm">
                      {new Date(sale.created_at).toLocaleString()}
                    </p>
                  </div>
                  <div>
                    <p className="text-sm font-medium text-muted-foreground">
                      Cashier
                    </p>
                    <p className="text-sm">{sale.cashier_email}</p>
                  </div>
                  <div className="col-span-2">
                    <p className="text-sm font-medium text-muted-foreground">
                      Sale ID
                    </p>
                    <code className="text-sm bg-muted px-1 py-0.5 rounded">
                      {sale.id}
                    </code>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Sale Items */}
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Items Sold</CardTitle>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Item</TableHead>
                      <TableHead className="text-right">Qty</TableHead>
                      <TableHead className="text-right">Unit Price</TableHead>
                      <TableHead className="text-right">Total</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {sale.items.length > 0 ? (
                      sale.items.map((item, index) => (
                        <TableRow key={index}>
                          <TableCell className="font-medium">
                            {item.product_name}
                          </TableCell>
                          <TableCell className="text-right">
                            {item.quantity}
                          </TableCell>
                          <TableCell className="text-right">
                            GHS {item.unit_price.toFixed(2)}
                          </TableCell>
                          <TableCell className="text-right">
                            GHS {item.subtotal.toFixed(2)}
                          </TableCell>
                        </TableRow>
                      ))
                    ) : (
                      <TableRow>
                        <TableCell
                          colSpan={4}
                          className="text-center py-6 text-muted-foreground"
                        >
                          No items recorded.
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>

                <Separator className="my-4" />

                <div className="flex justify-between items-center">
                  <span className="text-lg font-semibold">Total Amount:</span>
                  <span className="text-2xl font-bold">
                    GHS {sale.total.toFixed(2)}
                  </span>
                </div>
              </CardContent>
            </Card>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
