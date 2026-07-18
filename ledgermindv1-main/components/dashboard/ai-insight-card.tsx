"use client"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Brain,
  TrendingUp,
  AlertTriangle,
  BarChart3,
  Package,
  FileText,
  Check,
  X,
  Clock,
} from "lucide-react"
import { useState, type ReactNode } from "react"

export type LedmiInsightType = "reorder" | "anomaly" | "margin" | "brief" | "trend"
export type LedmiInsightStatus = "pending" | "actioned" | "dismissed" | "snoozed"

export interface LedmiInsight {
  id: string
  business_id: string
  branch_id: string | null
  insight_type: LedmiInsightType
  title: string
  description: string
  confidence_score: number | null
  priority: string
  status: LedmiInsightStatus
  is_read: boolean
  push_eligible: boolean
  data: Record<string, unknown>
  generated_at: string
  actioned_at: string | null
  dismissed_at: string | null
  actor_id: string | null
  created_at: string
  updated_at: string
}

interface AIInsightCardProps {
  insight: LedmiInsight
  onStatusChange?: (id: string, status: LedmiInsightStatus) => void
}

const TYPE_ICON: Record<LedmiInsightType, ReactNode> = {
  reorder: <Package className="h-4 w-4 text-primary" />,
  anomaly: <AlertTriangle className="h-4 w-4 text-destructive" />,
  margin: <BarChart3 className="h-4 w-4 text-primary" />,
  brief: <FileText className="h-4 w-4 text-primary" />,
  trend: <TrendingUp className="h-4 w-4 text-primary" />,
}

const TYPE_LABEL: Record<LedmiInsightType, string> = {
  reorder: "Reorder",
  anomaly: "Anomaly",
  margin: "Margin",
  brief: "Brief",
  trend: "Trend",
}

const PRIORITY_VARIANT: Record<string, "default" | "secondary" | "destructive"> = {
  low: "secondary",
  medium: "default",
  high: "default",
  critical: "destructive",
}

export function AIInsightCard({ insight, onStatusChange }: AIInsightCardProps) {
  const [status, setStatus] = useState<LedmiInsightStatus>(insight.status)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function patchStatus(next: LedmiInsightStatus) {
    setBusy(next)
    setError(null)
    try {
      const res = await fetch(`/api/ledmi/insights/${insight.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: next }),
      })
      if (!res.ok) {
        const data = (await res.json().catch(() => ({}))) as { error?: string }
        throw new Error(data.error || `Request failed (${res.status})`)
      }
      setStatus(next)
      onStatusChange?.(insight.id, next)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(null)
    }
  }

  const isPending = status === "pending"

  return (
    <Card className={isPending ? "border-primary/50 bg-primary/5" : ""}>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-center gap-2">
            {TYPE_ICON[insight.insight_type] ?? <Brain className="h-4 w-4 text-primary" />}
            <Badge variant={PRIORITY_VARIANT[insight.priority] ?? "default"} className="text-xs">
              {TYPE_LABEL[insight.insight_type]}
            </Badge>
            {insight.priority === "critical" && (
              <Badge variant="destructive" className="text-xs">Critical</Badge>
            )}
          </div>
          {isPending && (
            <div className="flex gap-1">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => patchStatus("actioned")}
                disabled={busy !== null}
                className="h-6 px-2 text-xs"
              >
                {busy === "actioned" ? "..." : <Check className="h-3 w-3" />}
                <span className="ml-1">Act</span>
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => patchStatus("snoozed")}
                disabled={busy !== null}
                className="h-6 px-2 text-xs"
              >
                {busy === "snoozed" ? "..." : <Clock className="h-3 w-3" />}
                <span className="ml-1">Snooze</span>
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => patchStatus("dismissed")}
                disabled={busy !== null}
                className="h-6 px-2 text-xs"
              >
                {busy === "dismissed" ? "..." : <X className="h-3 w-3" />}
                <span className="ml-1">Dismiss</span>
              </Button>
            </div>
          )}
        </div>
        <CardTitle className="text-base">{insight.title}</CardTitle>
        <p className="text-sm text-muted-foreground">{insight.description}</p>
      </CardHeader>
      <CardContent className="pt-0 space-y-2">
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <span>{new Date(insight.generated_at).toLocaleDateString()}</span>
          {insight.confidence_score != null && (
            <>
              <span>&bull;</span>
              <span>{Math.round(insight.confidence_score * 100)}% confidence</span>
            </>
          )}
          {status !== "pending" && (
            <>
              <span>&bull;</span>
              <Badge variant="secondary" className="text-xs capitalize">{status}</Badge>
            </>
          )}
        </div>
        {error && <p className="text-xs text-destructive">{error}</p>}
      </CardContent>
    </Card>
  )
}
