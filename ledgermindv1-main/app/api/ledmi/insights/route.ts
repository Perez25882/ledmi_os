import { NextResponse } from "next/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import { getInsights } from "@/lib/supabase/data/insights"
import { generateProactiveInsights } from "@/lib/nvidia-ai"

export async function GET() {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    if (!canAccessPage(context.roleName, "ai")) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const insights = await getInsights(context.businessId, context.branchId)
    let aiSummary: string | null = null
    let aiRecommendation: string | null = null

    try {
      const proactive = await generateProactiveInsights(insights)
      aiSummary = proactive?.summary ?? null
      aiRecommendation = proactive?.recommendation ?? null
    } catch (err) {
      console.error("Proactive AI generation failed:", err)
    }

    return NextResponse.json({
      ...insights,
      ai_summary: aiSummary,
      ai_recommendation: aiRecommendation,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
