"use client"

import { useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

export function SalesFilter() {
  const router = useRouter()
  const params = useSearchParams()
  const [from, setFrom] = useState(params.get("from") || "")
  const [to, setTo] = useState(params.get("to") || "")

  function apply() {
    const query = new URLSearchParams()
    if (from) query.set("from", from)
    if (to) query.set("to", to)
    router.push(`/dashboard/sales?${query.toString()}`)
  }

  function clear() {
    setFrom("")
    setTo("")
    router.push("/dashboard/sales")
  }

  return (
    <div className="flex flex-wrap items-end gap-2">
      <div className="space-y-1">
        <label className="text-xs font-medium">From</label>
        <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
      </div>
      <div className="space-y-1">
        <label className="text-xs font-medium">To</label>
        <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
      </div>
      <Button onClick={apply}>Filter</Button>
      <Button variant="outline" onClick={clear}>
        Clear
      </Button>
    </div>
  )
}
