import { AuthLayout } from "@/components/auth/auth-layout"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Smartphone } from "lucide-react"
import { SignOutButton } from "@/components/auth/sign-out-button"
import { createServerClientForUser } from "@/lib/supabase/server"
import { redirect } from "next/navigation"

export default async function CashierRedirectPage() {
  const supabase = await createServerClientForUser()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect("/auth/sign-in")
  }

  return (
    <AuthLayout>
      <Card className="border-border/60 shadow-sm">
        <CardHeader className="text-center pb-4">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-primary/10">
            <Smartphone className="h-7 w-7 text-primary" />
          </div>
          <CardTitle className="text-2xl font-bold tracking-tight">
            Use the POS App
          </CardTitle>
          <CardDescription>
            Cashier accounts don&apos;t have access to the web dashboard.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-center text-sm text-muted-foreground">
            The LedgerMind dashboard is for owners, managers, and accountants.
            As a cashier, you can process sales, accept payments, and print
            receipts directly from the LedgerMind POS app on your device.
          </p>
          <div className="rounded-lg border border-border/60 bg-muted/50 p-4 text-sm">
            <p className="font-medium text-foreground">Signed in as</p>
            <p className="text-muted-foreground">{user.email}</p>
          </div>
          <form action="/auth/sign-out" method="POST" className="hidden" />
          <SignOutButton />
        </CardContent>
      </Card>
    </AuthLayout>
  )
}
