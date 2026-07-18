import { NextRequest, NextResponse } from "next/server"
import { createServerClientForUser } from "@/lib/supabase/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"

type InsightStatus = "actioned" | "dismissed" | "snoozed"

const VALID_STATUSES: InsightStatus[] = ["actioned", "dismissed", "snoozed"]

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    if (!canAccessPage(context.roleName, "ai")) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const { id } = await params
    const body = (await request.json()) as { status?: string }
    if (!body.status || !VALID_STATUSES.includes(body.status as InsightStatus)) {
      return NextResponse.json(
        { error: "Invalid status. Must be one of: actioned, dismissed, snoozed" },
        { status: 400 }
      )
    }

    const status = body.status as InsightStatus
    const client = await createServerClientForUser()
    const now = new Date().toISOString()

    const update: Record<string, unknown> = {
      status,
      actor_id: context.userId,
      updated_at: now,
      is_read: true,
    }
    if (status === "actioned") update.actioned_at = now
    if (status === "dismissed") update.dismissed_at = now

    const { data, error } = await client
      .from("ai_insights")
      .update(update)
      .eq("id", id)
      .eq("business_id", context.businessId)
      .select()
      .single()

    if (error) {
      // PGRST116 = no rows matched; 42P01 = table missing (D1 migration not landed)
      if (error.code === "PGRST116" || error.code === "42P01") {
        return NextResponse.json({ error: "Insight not found" }, { status: 404 })
      }
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    // Best-effort audit log; activity_logs may not exist yet
    try {
      await client.from("activity_logs").insert({
        business_id: context.businessId,
        actor_id: context.userId,
        action: `insight_${status}`,
        entity_table: "ai_insights",
        entity_id: id,
        metadata: { insight_type: data.insight_type, title: data.title },
      })
    } catch (logError) {
      console.error("activity_logs insert failed:", logError)
    }

    return NextResponse.json(data)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
