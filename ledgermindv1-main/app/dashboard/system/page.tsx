import { requirePageAccess } from "@/lib/supabase/guards"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Server } from "lucide-react"

export default async function SystemPage() {
  const context = await requirePageAccess("system")

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-foreground flex items-center gap-2">
          <Server className="h-7 w-7 text-primary" />
          System
        </h1>
        <p className="text-muted-foreground text-sm sm:text-base">
          Platform configuration and integrations
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Integrations</CardTitle>
          <CardDescription>Connected services</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-sm">Supabase</p>
              <p className="text-xs text-muted-foreground">Database &amp; Auth</p>
            </div>
            <Badge>Connected</Badge>
          </div>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-sm">Paystack</p>
              <p className="text-xs text-muted-foreground">Payments</p>
            </div>
            <Badge variant="secondary">Pending</Badge>
          </div>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-sm">NVIDIA NIM</p>
              <p className="text-xs text-muted-foreground">Ledmi AI</p>
            </div>
            <Badge variant="secondary">Pending</Badge>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Business Context</CardTitle>
          <CardDescription>Current session details</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Business ID</span>
            <code className="text-xs bg-muted px-2 py-1 rounded">{context.businessId.slice(0, 12)}</code>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Role</span>
            <Badge variant="secondary" className="capitalize">{context.roleName}</Badge>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground text-sm">Branches</span>
            <span className="font-medium text-sm">{context.branches.length}</span>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
