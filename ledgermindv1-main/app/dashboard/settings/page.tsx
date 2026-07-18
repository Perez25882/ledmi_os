import { redirect } from "next/navigation"
import { requirePageAccess } from "@/lib/supabase/guards"
import { createServiceClient } from "@/lib/supabase/server"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Settings, User, Building2 } from "lucide-react"

export default async function SettingsPage() {
  const context = await requirePageAccess("settings")

  const serviceClient = createServiceClient()
  const { data: business } = await serviceClient
    .from("businesses")
    .select("name")
    .eq("id", context.businessId)
    .single()

  return (
    <div className="space-y-6 max-w-3xl mx-auto">
      <div>
        <h1 className="text-3xl font-bold text-foreground flex items-center gap-2">
          <Settings className="h-8 w-8 text-primary" />
          Settings
        </h1>
        <p className="text-muted-foreground">Your account and business context</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <User className="h-5 w-5" />
            Profile
          </CardTitle>
          <CardDescription>Your signed-in account details</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label className="text-muted-foreground text-xs">Email</Label>
              <p className="font-medium">{context.email}</p>
            </div>
            <div>
              <Label className="text-muted-foreground text-xs">Role</Label>
              <div>
                <Badge variant="secondary" className="capitalize">
                  {context.roleName}
                </Badge>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Building2 className="h-5 w-5" />
            Business
          </CardTitle>
          <CardDescription>Business and branch you are currently working in</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label className="text-muted-foreground text-xs">Business</Label>
              <p className="font-medium">{business?.name || "—"}</p>
            </div>
            <div>
              <Label className="text-muted-foreground text-xs">Branch</Label>
              <p className="font-medium">
                {context.branches.find((b) => b.id === context.branchId)?.name || "—"}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
