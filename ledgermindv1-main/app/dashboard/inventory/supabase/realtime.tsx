"use client"

import { useEffect } from "react"
import { createBrowserClient } from "@supabase/ssr"
import { toast } from "sonner"

export function InventoryRealtime({ branchId }: { branchId: string }) {
  useEffect(() => {
    const supabase = createBrowserClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    )

    const channel = supabase
      .channel("inventory-changes")
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "inventory", filter: `branch_id=eq.${branchId}` },
        (payload) => {
          const newRow = payload.new as { quantity?: number; product_id?: string }
          if (typeof newRow.quantity === "number" && newRow.product_id) {
            toast.info("Stock updated", {
              description: `Product ${newRow.product_id} now has ${newRow.quantity} units in stock.`,
            })
          }
        }
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [branchId])

  return null
}
