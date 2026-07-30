"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { getSaleItemsForRefundAction, createRefundAction } from "./actions"

interface SaleItem {
  id: string
  product_name: string
  quantity: number
  refunded_quantity: number
  unit_price: number
}

export function RefundsClient() {
  const [saleId, setSaleId] = useState("")
  const [items, setItems] = useState<SaleItem[]>([])
  const [selected, setSelected] = useState<Record<string, number>>({})
  const [reason, setReason] = useState("")
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  async function lookupSale() {
    setMessage(null)
    try {
      const data = await getSaleItemsForRefundAction(saleId)
      setItems(data)
      setSelected({})
    } catch (err) {
      setMessage(err instanceof Error ? err.message : String(err))
    }
  }

  async function submitRefund() {
    setLoading(true)
    setMessage(null)

    const refundItems = Object.entries(selected)
      .filter(([, qty]) => qty > 0)
      .map(([saleItemId, quantity]) => ({ saleItemId, quantity }))

    if (refundItems.length === 0) {
      setMessage("Select at least one item to refund")
      setLoading(false)
      return
    }

    try {
      await createRefundAction({ saleId, reason, items: refundItems })
      setMessage("Refund processed successfully")
      setItems([])
      setSelected({})
      setSaleId("")
      setReason("")
    } catch (err) {
      setMessage(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Refunds & Returns</h1>
        <p className="text-muted-foreground text-sm sm:text-base">Process returns against completed sales</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Lookup Sale</CardTitle>
          <CardDescription>Enter the sale ID to see refundable items</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2">
            <Input value={saleId} onChange={(e) => setSaleId(e.target.value)} placeholder="Sale ID" />
            <Button onClick={lookupSale} disabled={!saleId.trim()}>
              Lookup
            </Button>
          </div>
        </CardContent>
      </Card>

      {items.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Items</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Product</TableHead>
                  <TableHead>Sold</TableHead>
                  <TableHead>Already Refunded</TableHead>
                  <TableHead>Refund Qty</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((item) => {
                  const max = item.quantity - item.refunded_quantity
                  return (
                    <TableRow key={item.id}>
                      <TableCell>{item.product_name}</TableCell>
                      <TableCell>{item.quantity}</TableCell>
                      <TableCell>{item.refunded_quantity}</TableCell>
                      <TableCell>
                        <Input
                          type="number"
                          min={0}
                          max={max}
                          value={selected[item.id] ?? 0}
                          onChange={(e) => {
                            const qty = Math.min(parseInt(e.target.value || "0", 10), max)
                            setSelected((prev) => ({ ...prev, [item.id]: qty }))
                          }}
                          className="w-24"
                        />
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason (optional)" />
            <Button onClick={submitRefund} disabled={loading}>
              Process Refund
            </Button>
          </CardContent>
        </Card>
      )}

      {message && (
        <div
          className={`rounded-md p-3 text-sm ${
            message.includes("success")
              ? "bg-green-100 text-green-800"
              : "bg-destructive/15 text-destructive"
          }`}
        >
          {message}
        </div>
      )}
    </div>
  )
}
