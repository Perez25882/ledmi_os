import "server-only"
import { LedmiInsights } from "@/lib/supabase/data/insights"

const NVIDIA_API_URL =
  process.env.NVIDIA_API_URL || "https://integrate.api.nvidia.com/v1/chat/completions"
const NVIDIA_MODEL = process.env.NVIDIA_MODEL || "meta/llama-3.1-8b-instruct"

export interface ProactiveAiResult {
  summary: string
  recommendation: string
}

export async function askNVIDIA(
  systemPrompt: string,
  userPrompt: string
): Promise<string | null> {
  const apiKey = process.env.NVIDIA_API_KEY
  if (!apiKey) return null

  const res = await fetch(NVIDIA_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: NVIDIA_MODEL,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.3,
      max_tokens: 1500,
      top_p: 0.7,
    }),
  })

  if (!res.ok) {
    const text = await res.text()
    throw new Error(`NVIDIA API error ${res.status}: ${text}`)
  }

  const data = (await res.json()) as {
    choices?: { message?: { content?: string } }[]
  }

  return data.choices?.[0]?.message?.content?.trim() || null
}

export async function generateProactiveInsights(
  insights: LedmiInsights
): Promise<ProactiveAiResult | null> {
  const systemPrompt = `You are Ledmi, a proactive AI retail assistant for LedgerMind OS. You receive a daily business snapshot and write a concise executive summary and one concrete recommendation for the owner or manager. Base everything on the numbers provided. Never invent data. Keep the summary under 120 words and the recommendation under 80 words.`

  const userPrompt = `Today's business snapshot (GHS):
${JSON.stringify(insights, null, 2)}

Return a JSON object with exactly two keys: "summary" and "recommendation". Both values must be plain strings, not nested objects. Do not include markdown, code fences, or explanation. Example: {"summary":"...","recommendation":"..."}`

  const raw = await askNVIDIA(systemPrompt, userPrompt)
  if (!raw) return null

  const cleaned = raw
    .replace(/^```(?:json)?\s*/, "")
    .replace(/\s*```$/, "")
    .trim()

  try {
    const parsed = JSON.parse(cleaned) as Record<string, unknown>
    const summary = typeof parsed.summary === "string" ? parsed.summary.trim() : ""
    const recommendation = typeof parsed.recommendation === "string" ? parsed.recommendation.trim() : ""
    if (summary && recommendation) {
      return { summary, recommendation }
    }
  } catch {
    // fall through to heuristic
  }

  // Heuristic fallback: first two sentences or lines.
  const sentences = cleaned
    .replace(/\{|\}/g, "")
    .split(/[.!?]/)
    .map((s) => s.trim())
    .filter(Boolean)
  if (sentences.length >= 2) {
    return {
      summary: sentences[0] + ".",
      recommendation: sentences.slice(1).join(". ") + ".",
    }
  }

  const lines = cleaned.split(/\n/).map((s) => s.trim()).filter(Boolean)
  return {
    summary: lines[0] || cleaned,
    recommendation: lines.slice(1).join(" ") || "No recommendation generated.",
  }
}
