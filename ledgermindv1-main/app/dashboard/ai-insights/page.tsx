import { redirect } from "next/navigation"
import { createServerClientForUser } from "@/lib/supabase/server"

export default async function AIInsightsPage() {
  const supabase = await createServerClientForUser()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect("/auth/login")

  // Ledmi is the floating chat assistant; redirect to overview
  redirect("/dashboard/overview")
}
