import { createServerClient, type CookieOptions } from "@supabase/ssr"
import { NextResponse, type NextRequest } from "next/server"

const publicPaths = [
  "/",
  "/auth/login",
  "/auth/sign-in",
  "/auth/sign-up",
  "/auth/sign-up-success",
  "/auth/error",
  "/pricing",
]

const staticAssetPattern =
  /^\/_next\/|\.svg$|\.png$|\.jpg$|\.jpeg$|\.gif$|\.webp$|\.ico$/

function isPublicPath(pathname: string): boolean {
  if (pathname.startsWith("/_next/")) return true
  if (staticAssetPattern.test(pathname)) return true
  if (pathname.startsWith("/api/auth/")) return true
  return publicPaths.some(
    (p) => pathname === p || pathname.startsWith(`${p}/`)
  )
}

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          request.cookies.set({ name, value, ...options })
          response = NextResponse.next({
            request: { headers: request.headers },
          })
          response.cookies.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          request.cookies.set({ name, value: "", ...options })
          response = NextResponse.next({
            request: { headers: request.headers },
          })
          response.cookies.set({ name, value: "", ...options })
        },
      },
    }
  )

  // Refresh session if expired and return updated cookies.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const pathname = request.nextUrl.pathname

  if (!user && !isPublicPath(pathname)) {
    const url = request.nextUrl.clone()
    url.pathname = "/auth/sign-in"
    url.searchParams.set("next", pathname)
    return NextResponse.redirect(url)
  }

  if (user && (pathname.startsWith("/auth") || pathname === "/")) {
    const url = request.nextUrl.clone()
    url.pathname = "/dashboard"
    return NextResponse.redirect(url)
  }

  return response
}
