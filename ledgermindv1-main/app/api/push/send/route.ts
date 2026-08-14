import { NextRequest, NextResponse } from "next/server"
import webpush from "web-push"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { hasPermission } from "@/lib/supabase/permissions"
import { getPushSubscriptionsForBusiness } from "@/lib/supabase/data/push"

function requireVapid() {
  const vapidPublic = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
  const vapidPrivate = process.env.VAPID_PRIVATE_KEY
  if (!vapidPublic || !vapidPrivate) {
    throw new Error("VAPID keys are not configured")
  }
  webpush.setVapidDetails("mailto:admin@ledgermind.io", vapidPublic, vapidPrivate)
}

// Only allow same-origin relative deep links. The service worker opens this URL
// on notification click, so an absolute/external URL would be a phishing vector.
function sanitizeDeepLink(raw: string | undefined): string {
  const fallback = "/dashboard/overview"
  if (!raw || typeof raw !== "string") return fallback
  if (!raw.startsWith("/") || raw.startsWith("//")) return fallback
  return raw
}

export async function POST(request: NextRequest) {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    // Broadcasting to every subscribed device is an operational action — restrict
    // it to roles that manage the business (owner/manager). Cashiers/accountants
    // must not be able to push notifications to all staff.
    if (!hasPermission(context.roleName, "manage_inventory")) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const body = (await request.json()) as { title?: string; body?: string; url?: string }
    const title = (body.title || "LedgerMind Alert").slice(0, 120)
    const messageBody = (body.body || "Something needs your attention.").slice(0, 300)
    const url = sanitizeDeepLink(body.url)

    requireVapid()
    const subscriptions = await getPushSubscriptionsForBusiness(context.businessId)
    const payload = JSON.stringify({ title, body: messageBody, url })

    const results = await Promise.all(
      subscriptions.map(async (sub) => {
        try {
          await webpush.sendNotification(
            { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
            payload
          )
          return { ok: true }
        } catch (e) {
          const err = e as { statusCode?: number; message?: string }
          return { ok: false, status: err.statusCode, message: err.message }
        }
      })
    )

    return NextResponse.json({ sent: subscriptions.length, results })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}