import { NextRequest, NextResponse } from "next/server"
import { getCurrentUserRoleContext } from "@/lib/supabase/data/user-context"
import { canAccessPage } from "@/lib/supabase/permissions"
import { askNVIDIA } from "@/lib/nvidia-ai"

function buildSystemPrompt(insights: any) {
  const summary = insights.today_summary
  const reorder = (insights.reorder_suggestions as any[])
    .map((i) => `${i.product_name}: ${i.current_quantity}/${i.reorder_level}`)
    .join("\n") || "None"
  const lowMargin = (insights.low_margin_products as any[])
    .map((i) => `${i.product_name}: ${i.margin_percent.toFixed(1)}%`)
    .join("\n") || "None"
  const topProducts = (summary.top_products as any[])
    .map((i) => `${i.product_name}: GHS ${i.total_revenue.toFixed(2)}`)
    .join("\n") || "None"

  return `You are Ledmi, an AI retail assistant for LedgerMind OS. Answer questions using ONLY the following real data.

Today's sales: GHS ${summary.revenue.toFixed(2)} across ${summary.sales_count} sales. AOV: GHS ${summary.average_order_value.toFixed(2)}.
Top products today:
${topProducts}

Reorder alerts:
${reorder}

Low margin products:
${lowMargin}

Keep answers concise and grounded in the numbers. If asked something outside the data, say you can only answer about sales, inventory, margins, and reordering.`
}



export async function POST(request: NextRequest) {
  try {
    const context = await getCurrentUserRoleContext()
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    if (!canAccessPage(context.roleName, "ai")) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const body = (await request.json()) as { question: string; insights: any }
    const { question, insights } = body
    if (!question || !insights) {
      return NextResponse.json({ error: "Missing question or insights" }, { status: 400 })
    }

    const systemPrompt = buildSystemPrompt(insights)
    let answer = await askNVIDIA(systemPrompt, question)

    if (!answer) {
      const q = question.toLowerCase()
      if (q.includes("reorder") || q.includes("stock") || q.includes("buy")) {
        const items = insights.reorder_suggestions as any[]
        answer =
          items.length === 0
            ? "No products need reordering right now. Stock levels are healthy."
            : "Consider reordering: " +
              items.map((i) => `${i.product_name} (order ${i.suggested_order})`).join(", ")
      } else if (q.includes("margin")) {
        const items = insights.low_margin_products as any[]
        answer =
          items.length === 0
            ? "All products have a healthy margin."
            : "Low margin products: " +
              items.map((i) => `${i.product_name} at ${i.margin_percent.toFixed(1)}%`).join(", ")
      } else if (q.includes("top")) {
        const items = insights.today_summary.top_products as any[]
        answer =
          items.length === 0
            ? "No sales recorded today."
            : "Top products today: " +
              items.map((i) => `${i.product_name} (GHS ${i.total_revenue.toFixed(2)})`).join(", ")
      } else if (q.includes("sale") || q.includes("revenue") || q.includes("today")) {
        const summary = insights.today_summary
        answer = `Today: GHS ${summary.revenue.toFixed(2)} revenue across ${summary.sales_count} sales. Average order value is GHS ${summary.average_order_value.toFixed(2)}.`
      } else if (q.includes("anomal") || q.includes("issue") || q.includes("alert")) {
        const anomalies = insights.anomalies as string[]
        answer = anomalies.length > 0 ? anomalies.join(" ") : "No anomalies detected."
      } else {
        answer =
          "I can help with sales, revenue, top products, stock reordering, and margin alerts. What would you like to know?"
      }
    }

    return NextResponse.json({ answer })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
