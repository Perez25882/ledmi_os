"use client"

import { useState } from "react"
import { Badge } from "@/components/ui/badge"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import type { Sale } from "@/lib/supabase/data/sales"
import { SaleDetailsDialog } from "@/components/sales/sale-details-dialog"

interface SalesTableProps {
  sales: Sale[]
}

export function SalesTable({ sales }: SalesTableProps) {
  const [selectedSale, setSelectedSale] = useState<Sale | null>(null)
  const [open, setOpen] = useState(false)

  function handleRowClick(sale: Sale) {
    setSelectedSale(sale)
    setOpen(true)
  }

  return (
    <>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Invoice</TableHead>
            <TableHead>Date</TableHead>
            <TableHead>Cashier</TableHead>
            <TableHead>Method</TableHead>
            <TableHead>Total</TableHead>
            <TableHead>Items</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {sales.length > 0 ? (
            sales.map((sale) => (
              <TableRow
                key={sale.id}
                onClick={() => handleRowClick(sale)}
                className="cursor-pointer"
              >
                <TableCell className="font-medium">
                  {sale.invoice_number}
                </TableCell>
                <TableCell>
                  {new Date(sale.created_at).toLocaleString()}
                </TableCell>
                <TableCell>{sale.cashier_email}</TableCell>
                <TableCell>
                  <Badge
                    variant={
                      sale.payment_method === "cash" ? "secondary" : "outline"
                    }
                  >
                    {sale.payment_method}
                  </Badge>
                </TableCell>
                <TableCell>GHS {sale.total.toFixed(2)}</TableCell>
                <TableCell>{sale.items.length}</TableCell>
              </TableRow>
            ))
          ) : (
            <TableRow>
              <TableCell colSpan={6} className="text-center py-8">
                No sales found.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>

      <SaleDetailsDialog
        sale={selectedSale}
        open={open}
        onOpenChange={setOpen}
      />
    </>
  )
}
