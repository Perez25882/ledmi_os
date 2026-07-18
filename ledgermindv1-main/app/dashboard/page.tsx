import { redirect } from "next/navigation"
import { createServerClientForUser } from "@/lib/supabase/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { isCashier } from "@/lib/supabase/permissions"

export default async function DashboardRootPage() {
  const supabase = await createServerClientForUser()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    redirect("/auth/login")
  }

  const context = await getCurrentUserRoleContext()
  if (!context) {
    redirect("/onboarding")
  }

  if (isCashier(context.roleName)) {
    redirect("/auth/cashier-redirect")
  }

  redirect("/dashboard/overview")
}
