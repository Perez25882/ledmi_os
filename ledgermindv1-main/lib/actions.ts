"use server"

import { createServerClientForUser } from "@/lib/supabase/server"
import { redirect } from "next/navigation"

export async function logout() {
  const client = await createServerClientForUser()
  await client.auth.signOut()
  redirect("/auth/login")
}
