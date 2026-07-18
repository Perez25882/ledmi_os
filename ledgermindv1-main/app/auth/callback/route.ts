import { createServerClient, type CookieOptions } from "@supabase/ssr"
import { type NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const code = searchParams.get("code")
  const next = searchParams.get("next") ?? "/dashboard"

  if (code) {
    const cookieStore = await cookies()
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get(name: string) {
            return cookieStore.get(name)?.value
          },
          set(name: string, value: string, options: CookieOptions) {
            cookieStore.set({ name, value, ...options })
          },
          remove(name: string, options: CookieOptions) {
            cookieStore.set({ name, value: "", ...options })
          },
        },
      }
    )

    const { error } = await supabase.auth.exchangeCodeForSession(code)

    if (error) {
      const url = new URL("/auth/error", request.url)
      url.searchParams.set("error", error.message)
      return NextResponse.redirect(url)
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (user) {
      const { data: roleRows } = await supabase
        .from("user_business_roles")
        .select("custom_roles(name)")
        .eq("user_id", user.id)
        .limit(1)

      const roleName = (roleRows as any[])?.[0]?.custom_roles?.name as string | undefined
      if (roleName === "cashier") {
        return NextResponse.redirect(new URL("/auth/cashier-redirect", request.url))
      }
    }
  }

  return NextResponse.redirect(new URL(next, request.url))
}
