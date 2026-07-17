"use client"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { CheckCircle, Flame, Sparkles, Shield, Zap } from "lucide-react"

export function SetupGuide() {
  return (
    <div className="max-w-4xl mx-auto p-6 space-y-6">
      <Alert className="border-green-500 bg-green-50 dark:bg-green-950/20">
        <CheckCircle className="h-4 w-4 text-green-600" />
        <AlertTitle>LedgerMind is Ready! 🎉</AlertTitle>
        <AlertDescription>
          Your AI-powered inventory management system is fully configured with Firebase and Kimi AI.
        </AlertDescription>
      </Alert>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Flame className="h-5 w-5 text-orange-500" />
            Platform Features
          </CardTitle>
          <CardDescription>
            Everything you need to manage your inventory and grow your business.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-3">
              <h4 className="font-semibold flex items-center gap-2">
                <Shield className="h-4 w-4 text-primary" />
                Core Features
              </h4>
              <ul className="space-y-1 text-sm text-muted-foreground">
                <li>• Inventory Management & Tracking</li>
                <li>• Sales Recording & Analytics</li>
                <li>• Category Organization</li>
                <li>• Stock Level Monitoring & Alerts</li>
                <li>• Real-time Dashboard with KPIs</li>
                <li>• Comprehensive Reports</li>
              </ul>
            </div>
            <div className="space-y-3">
              <h4 className="font-semibold flex items-center gap-2">
                <Sparkles className="h-4 w-4 text-primary" />
                AI-Powered Features
              </h4>
              <ul className="space-y-1 text-sm text-muted-foreground">
                <li>• Kimi AI Business Analyst</li>
                <li>• Natural Language Queries</li>
                <li>• Sales Forecasting</li>
                <li>• Inventory Optimization</li>
                <li>• Trend Detection & Anomalies</li>
                <li>• Actionable Recommendations</li>
              </ul>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Zap className="h-5 w-5 text-yellow-500" />
            Getting Started
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid gap-3">
            <div className="flex items-start gap-3 p-3 bg-muted/50 rounded-lg">
              <div className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-primary-foreground text-xs font-bold">1</div>
              <div>
                <h4 className="font-medium text-sm">Add your inventory items</h4>
                <p className="text-xs text-muted-foreground">Start by adding your products, setting stock levels, and organizing categories.</p>
              </div>
            </div>
            <div className="flex items-start gap-3 p-3 bg-muted/50 rounded-lg">
              <div className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-primary-foreground text-xs font-bold">2</div>
              <div>
                <h4 className="font-medium text-sm">Record your sales</h4>
                <p className="text-xs text-muted-foreground">Log sales transactions — inventory updates automatically.</p>
              </div>
            </div>
            <div className="flex items-start gap-3 p-3 bg-muted/50 rounded-lg">
              <div className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-primary-foreground text-xs font-bold">3</div>
              <div>
                <h4 className="font-medium text-sm">Ask the AI for insights</h4>
                <p className="text-xs text-muted-foreground">Use natural language to get actionable business recommendations and forecasts.</p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}