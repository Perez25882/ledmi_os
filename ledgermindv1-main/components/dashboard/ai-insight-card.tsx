"use client"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Brain, TrendingUp, AlertTriangle, Lightbulb, BarChart3, Eye, EyeOff } from "lucide-react"
import { useState } from "react"

interface AIInsight {
  id: string
  insight_type: "forecast" | "anomaly" | "recommendation" | "trend"
  title: string
  description: string
  confidence_score?: number
  is_read: boolean
  created_at: string
  data?: Record<string, unknown>
}

interface AIInsightCardProps {
  insight: AIInsight
  onMarkAsRead?: (id: string) => void
}

export function AIInsightCard({ insight, onMarkAsRead }: AIInsightCardProps) {
  const [isRead, setIsRead] = useState(insight.is_read)
  const [isLoading, setIsLoading] = useState(false)

  const getInsightIcon = (type: string) => {
    switch (type) {
      case "forecast":
        return <TrendingUp className="h-4 w-4 text-primary" />
      case "anomaly":
        return <AlertTriangle className="h-4 w-4 text-destructive" />
      case "recommendation":
        return <Lightbulb className="h-4 w-4 text-primary" />
      case "trend":
        return <BarChart3 className="h-4 w-4 text-primary" />
      default:
        return <Brain className="h-4 w-4 text-primary" />
    }
  }

  const getInsightTypeLabel = (type: string) => {
    switch (type) {
      case "forecast":
        return "Forecast"
      case "anomaly":
        return "Anomaly"
      case "recommendation":
        return "Recommendation"
      case "trend":
        return "Trend"
      default:
        return "Insight"
    }
  }

  const handleMarkAsRead = async () => {
    if (isRead) return

    setIsLoading(true)
    try {
      // Mark insight as read via API (TODO: add dedicated endpoint)
      setIsRead(true)
      onMarkAsRead?.(insight.id)
    } catch (error) {
      console.error("Error marking insight as read:", error)
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <Card className={`transition-all ${!isRead ? "border-primary/50 bg-primary/5" : ""}`}>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-2">
            {getInsightIcon(insight.insight_type)}
            <Badge variant={isRead ? "secondary" : "default"} className="text-xs">
              {getInsightTypeLabel(insight.insight_type)}
            </Badge>
          </div>
          {!isRead && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleMarkAsRead}
              disabled={isLoading}
              className="h-6 px-2 text-xs"
            >
              {isLoading ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
              Mark as read
            </Button>
          )}
        </div>
        <CardTitle className="text-base">{insight.title}</CardTitle>
        <CardDescription className="text-sm">{insight.description}</CardDescription>
      </CardHeader>
      <CardContent className="pt-0">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span>{new Date(insight.created_at).toLocaleDateString()}</span>
            {insight.confidence_score && (
              <>
                <span>•</span>
                <span>{Math.round(insight.confidence_score * 100)}% confidence</span>
              </>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
