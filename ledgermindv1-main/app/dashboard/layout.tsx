import type React from "react"
import { redirect } from "next/navigation"
import { LedmiChat } from "@/components/ai-chat"
import { createServerClientForUser } from "@/lib/supabase/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { isCashier, canAccessAllBranches } from "@/lib/supabase/permissions"
import { getSelectedBranchId } from "@/lib/supabase/selected-branch"
import { SidebarProvider, SidebarInset, SidebarTrigger } from "@/components/ui/sidebar"
import { SupabaseSidebar } from "@/components/supabase-sidebar"
import { BranchProvider } from "@/components/branch-selector-provider"
import { BranchSelector } from "@/components/branch-selector"

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createServerClientForUser()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    redirect("/auth/login")
  }

  const supabaseContext = await getCurrentUserRoleContext()
  if (!supabaseContext) {
    redirect("/onboarding")
  }

  if (isCashier(supabaseContext.roleName)) {
    redirect("/auth/cashier-redirect")
  }

  const canAccessAll = canAccessAllBranches(supabaseContext.roleName)
  const selectedBranchId = canAccessAll
    ? await getSelectedBranchId(supabaseContext)
    : supabaseContext.branchId

  return (
    <SidebarProvider>
      <SupabaseSidebar context={supabaseContext} />

      <SidebarInset>
        <BranchProvider
          initialSelectedBranchId={selectedBranchId}
          branches={supabaseContext.branches}
          canAccessAll={canAccessAll}
        >
          <header className="flex h-16 shrink-0 items-center justify-between gap-4 border-b border-border bg-background/95 px-4 backdrop-blur-sm">
            <div className="flex items-center gap-3">
              <SidebarTrigger variant="outline" className="h-8 w-8" />
              <span className="hidden sm:inline text-sm font-medium text-muted-foreground">
                LedgerMind
              </span>
            </div>
            <BranchSelector />
          </header>

          <main className="flex-1 overflow-auto bg-muted/20 p-4 sm:p-6">
            {children}
          </main>

          <LedmiChat />
        </BranchProvider>
      </SidebarInset>
    </SidebarProvider>
  )
}
