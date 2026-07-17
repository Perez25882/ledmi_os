"use client"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Brain, Zap, CheckCircle, Sparkles } from "lucide-react"

export function AISetupGuide() {
  return (
    <div className="space-y-6">
      <Alert className="border-green-500 bg-green-50 dark:bg-green-950/20">
        <CheckCircle className="h-4 w-4 text-green-600" />
        <AlertTitle>AI Powered by Kimi 🎉</AlertTitle>
        <AlertDescription>
          Your AI assistant is powered by Kimi (Moonshot AI), a state-of-the-art language model
          fine-tuned for business analytics and inventory management insights.
        </AlertDescription>
      </Alert>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Brain className="h-5 w-5 text-green-600" />
            AI Assistant — Active
            <Badge variant="secondary">Kimi AI</Badge>
          </CardTitle>
          <CardDescription>
            Your AI assistant has access to advanced capabilities for business intelligence
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <h4 className="font-semibold text-green-600">✓ Available Features</h4>
              <ul className="space-y-1 text-sm text-muted-foreground">
                <li>• Natural language understanding</li>
                <li>• Complex business analysis</li>
                <li>• Predictive insights and forecasting</li>
                <li>• Personalized recommendations</li>
                <li>• Advanced pattern recognition</li>
                <li>• Contextual business advice</li>
                <li>• Multi-turn conversations</li>
                <li>• Real-time data analysis</li>
              </ul>
            </div>
            <div className="space-y-2">
              <h4 className="font-semibold text-cyan-600">💡 Try These Queries</h4>
              <ul className="space-y-1 text-sm text-muted-foreground">
                <li>• &quot;Analyze my profit margins&quot;</li>
                <li>• &quot;Show me sales trends and forecast&quot;</li>
                <li>• &quot;Which products should I focus on?&quot;</li>
                <li>• &quot;How can I optimize inventory levels?&quot;</li>
                <li>• &quot;Predict next month&apos;s revenue&quot;</li>
                <li>• &quot;What items need restocking urgently?&quot;</li>
              </ul>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Zap className="h-5 w-5 text-yellow-600" />
            How It Works
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <div className="p-1.5 bg-primary/10 rounded-full">
                <Sparkles className="h-4 w-4 text-primary" />
              </div>
              <div>
                <h4 className="font-medium text-sm">Secure Server-Side Processing</h4>
                <p className="text-sm text-muted-foreground">
                  All AI queries are processed server-side. Your data and API keys are never exposed to the browser.
                </p>
              </div>
            </div>
            <div className="flex items-start gap-3">
              <div className="p-1.5 bg-primary/10 rounded-full">
                <Brain className="h-4 w-4 text-primary" />
              </div>
              <div>
                <h4 className="font-medium text-sm">Real Business Data</h4>
                <p className="text-sm text-muted-foreground">
                  The AI analyzes your actual inventory, sales, and financial data to provide personalized, actionable insights.
                </p>
              </div>
            </div>
            <div className="flex items-start gap-3">
              <div className="p-1.5 bg-primary/10 rounded-full">
                <CheckCircle className="h-4 w-4 text-primary" />
              </div>
              <div>
                <h4 className="font-medium text-sm">Confidence Scoring</h4>
                <p className="text-sm text-muted-foreground">
                  Each AI response includes a confidence score so you know how reliable the analysis is.
                </p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}