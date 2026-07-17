"use client"

import { useEffect, useState } from "react"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { AlertTriangle, TrendingUp, Package, MessageSquare, Lightbulb } from "lucide-react"

interface Insights {
  reorder_suggestions: Array<{
    product_name: string
    current_quantity: number
    reorder_level: number
    suggested_order: number
  }>
  low_margin_products: Array<{
    product_name: string
    margin_percent: number
  }>
  today_summary: {
    revenue: number
    sales_count: number
    average_order_value: number
    top_products: Array<{
      product_name: string
      total_quantity: number
      total_revenue: number
    }>
  }
  anomalies: string[]
  ai_summary?: string
  ai_recommendation?: string
}

export default function SupabaseAiInsightsPage() {
  const [insights, setInsights] = useState<Insights | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [question, setQuestion] = useState("")
  const [answer, setAnswer] = useState<string | null>(null)
  const [answerLoading, setAnswerLoading] = useState(false)

  useEffect(() => {
    fetch("/api/ledmi/insights")
      .then((res) => res.json())
      .then((data) => {
        if (data.error) throw new Error(data.error)
        setInsights(data)
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [])

  async function askQuestion() {
    if (!question.trim() || !insights) return
    setAnswerLoading(true)
    setAnswer(null)

    try {
      const res = await fetch("/api/ledmi/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, insights }),
      })
      const data = await res.json()
      setAnswer(data.answer || "No answer available.")
    } catch (err) {
      setAnswer(err instanceof Error ? err.message : String(err))
    } finally {
      setAnswerLoading(false)
    }
  }

  if (loading) return <p className="text-muted-foreground">Loading insights...</p>
  if (error) return <p className="text-destructive">Error: {error}</p>
  if (!insights) return <p className="text-muted-foreground">No insights available.</p>

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold text-foreground">Ledmi Insights</h1>
        <p className="text-muted-foreground text-sm sm:text-base">
          AI-powered overview of your business
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Today&apos;s Revenue</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              GHS {insights.today_summary.revenue.toFixed(2)}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Sales Today</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{insights.today_summary.sales_count}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Reorder Alerts</CardTitle>
            <AlertTriangle className="h-4 w-4 text-destructive" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-destructive">
              {insights.reorder_suggestions.length}
            </div>
          </CardContent>
        </Card>
      </div>

      {insights.ai_summary && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Lightbulb className="h-4 w-4 text-yellow-500" /> Proactive AI Insight
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <p className="text-sm text-muted-foreground">{insights.ai_summary}</p>
            {insights.ai_recommendation && (
              <p className="text-sm font-medium">{insights.ai_recommendation}</p>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Package className="h-4 w-4" /> Reorder Suggestions
          </CardTitle>
        </CardHeader>
        <CardContent>
          {insights.reorder_suggestions.length > 0 ? (
            <div className="flex flex-wrap gap-2">
              {insights.reorder_suggestions.map((item, index) => (
                <Badge key={index} variant="destructive">
                  {item.product_name} ({item.current_quantity} / {item.reorder_level}) → order{" "}
                  {item.suggested_order}
                </Badge>
              ))}
            </div>
          ) : (
            <p className="text-muted-foreground">No reorder suggestions.</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Low Margin Products</CardTitle>
        </CardHeader>
        <CardContent>
          {insights.low_margin_products.length > 0 ? (
            <div className="flex flex-wrap gap-2">
              {insights.low_margin_products.map((item, index) => (
                <Badge key={index} variant="secondary">
                  {item.product_name} ({item.margin_percent.toFixed(1)}%)
                </Badge>
              ))}
            </div>
          ) : (
            <p className="text-muted-foreground">No low-margin products.</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <MessageSquare className="h-4 w-4" /> Ask Ledmi
          </CardTitle>
          <CardDescription>
            Ask a question about today&apos;s sales and inventory.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder="e.g. What should I reorder today?"
              onKeyDown={(e) => e.key === "Enter" && askQuestion()}
            />
            <Button onClick={askQuestion} disabled={answerLoading}>
              Ask
            </Button>
          </div>
          {answer && (
            <div className="rounded-md bg-muted p-3 text-sm">
              <p className="font-medium mb-1">Ledmi</p>
              {answer}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
