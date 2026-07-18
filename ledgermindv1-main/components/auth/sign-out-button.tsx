"use client"

import { useRouter } from "next/navigation"
import { createBrowserClient } from "@supabase/ssr"
import { Button } from "@/components/ui/button"
import { LogOut } from "lucide-react"

export function SignOutButton() {
  const router = useRouter()
  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )

  async function handleSignOut() {
    await supabase.auth.signOut()
    router.push("/auth/sign-in")
    router.refresh()
  }

  return (
    <Button variant="outline" className="w-full h-11 font-medium" onClick={handleSignOut}>
      <LogOut className="mr-2 h-4 w-4" />
      Sign out and switch account
    </Button>
  )
}
