"use client"

import { useTransition } from "react"
import { Button } from "@/components/ui/button"
import { FileDown } from "lucide-react"
import { exportSalesCsv } from "./export"

export function ExportSalesButton({ from, to }: { from?: string; to?: string }) {
  const [isPending, startTransition] = useTransition()

  function download() {
    startTransition(async () => {
      const csv = await exportSalesCsv(from, to)
      const blob = new Blob([csv], { type: "text/csv" })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `sales-${new Date().toISOString().split("T")[0]}.csv`
      a.click()
      URL.revokeObjectURL(url)
    })
  }

  return (
    <Button variant="outline" disabled={isPending} onClick={download}>
      <FileDown className="h-4 w-4 mr-2" />
      {isPending ? "Exporting..." : "Export CSV"}
    </Button>
  )
}
