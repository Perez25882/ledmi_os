"use client"

import { useCallback, useEffect, useState } from "react"
import { Sparkles, RefreshCw } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { cn } from "@/lib/utils"

export function BusinessSnapshot() {
  const [snapshot, setSnapshot] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchSnapshot = useCallback(async () => {
    setError(null)
    try {
      const res = await fetch("/api/ledmi/snapshot", { cache: "no-store" })
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as { error?: string } | null
        throw new Error(body?.error || `Request failed (${res.status})`)
      }
      const data = (await res.json()) as { snapshot?: string }
      setSnapshot(data.snapshot ?? null)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load snapshot")
    } finally {
      setLoading(false)
    }
  }, [])

  // `loading` starts true, so the initial fetch does not need to set it —
  // keeping the effect free of a synchronous setState. Manual refreshes go
  // through handleRefresh, which restores the spinner first.
  useEffect(() => {
    fetchSnapshot()
  }, [fetchSnapshot])

  const handleRefresh = useCallback(() => {
    setLoading(true)
    void fetchSnapshot()
  }, [fetchSnapshot])

  return (
    <Card
      className={cn(
        "border-primary/20 bg-gradient-to-br from-primary/10 via-primary/5 to-transparent",
        "shadow-sm"
      )}
    >
      <CardContent className="flex items-start gap-4 px-6">
        <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/15">
          <Sparkles className="h-5 w-5 text-primary" />
        </div>

        <div className="min-w-0 flex-1 space-y-1.5">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold text-foreground">Business Snapshot</span>
            <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-primary">
              Ledmi AI
            </span>
          </div>

          {loading ? (
            <div className="space-y-2">
              <p className="text-xs text-muted-foreground">Analyzing your business today…</p>
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-[90%]" />
              <Skeleton className="h-4 w-[75%]" />
            </div>
          ) : error ? (
            <p className="text-sm text-muted-foreground">
              Couldn&apos;t generate a snapshot right now. {error}
            </p>
          ) : (
            <p className="text-sm leading-relaxed text-foreground/90">{snapshot}</p>
          )}
        </div>

        <Button
          variant="ghost"
          size="sm"
          onClick={handleRefresh}
          disabled={loading}
          className="shrink-0 text-muted-foreground hover:text-foreground"
        >
          <RefreshCw className={cn("h-4 w-4", loading && "animate-spin")} />
          Refresh
        </Button>
      </CardContent>
    </Card>
  )
}
