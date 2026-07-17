import { NextRequest, NextResponse } from "next/server"
import webpush from "web-push"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { getPushSubscriptionsForBusiness } from "@/lib/supabase/data/push"

function requireVapid() {
  const vapidPublic = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
  const vapidPrivate = process.env.VAPID_PRIVATE_KEY
  if (!vapidPublic || !vapidPrivate) {
    throw new Error("VAPID keys are not configured")
  }
  webpush.setVapidDetails(
    "mailto:admin@ledgermind.io",
    vapidPublic,
    vapidPrivate
  )
}

export async function POST(request: NextRequest) {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const body = (await request.json()) as { title?: string; body?: string; url?: string }
    const title = body.title || "LedgerMind Alert"
    const messageBody = body.body || "Something needs your attention."
    const url = body.url || "/dashboard/overview"

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
