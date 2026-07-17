import { NextRequest, NextResponse } from "next/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { savePushSubscription } from "@/lib/supabase/data/push"

export async function POST(request: NextRequest) {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const body = (await request.json()) as {
      endpoint: string
      p256dh: string
      auth: string
    }

    await savePushSubscription(context.userId, context.businessId, body)
    return NextResponse.json({ ok: true })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
