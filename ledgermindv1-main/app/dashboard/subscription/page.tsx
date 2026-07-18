import { requirePageAccess } from "@/lib/supabase/guards"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { CreditCard } from "lucide-react"

export default async function SubscriptionPage() {
  const context = await requirePageAccess("subscription")

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-foreground flex items-center gap-2">
          <CreditCard className="h-7 w-7 text-primary" />
          Subscription
        </h1>
        <p className="text-muted-foreground text-sm sm:text-base">
          Manage your LedgerMind billing plan
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Current Plan</CardTitle>
          <CardDescription>Your active subscription tier</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Plan</span>
            <Badge variant="secondary">MVP Pilot</Badge>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Status</span>
            <Badge>Active</Badge>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Business</span>
            <span className="font-medium text-sm">{context.businessId.slice(0, 8)}</span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Billing</CardTitle>
          <CardDescription>Payment method and invoice history</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground text-sm">
            Billing integration with Paystack will be available after the pilot phase.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
