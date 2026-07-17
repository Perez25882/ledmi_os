/**
 * AI Service — NVIDIA NIM Integration
 * "Ledmi" — LedgerMind's intelligent assistant
 *
 * This service is used server-side only (via API routes).
 */

const NVIDIA_API_URL =
  process.env.NVIDIA_API_URL || "https://integrate.api.nvidia.com/v1/chat/completions"
const NVIDIA_MODEL = process.env.NVIDIA_MODEL || "meta/llama-3.1-8b-instruct"

interface BusinessData {
  inventory: Array<Record<string, unknown>>
  sales: Array<Record<string, unknown>>
  stockMovements: Array<Record<string, unknown>>
  categories: Array<Record<string, unknown>>
}

interface AIAnalysisRequest {
  query: string
  businessData: BusinessData
  conversationHistory?: Array<any>
}

export interface AIToolCall {
  id: string
  type: "function"
  function: {
    name: string
    arguments: string
  }
}

export interface AIAnalysisResult {
  answer?: string
  toolCalls?: AIToolCall[]
  assistantMessage?: any
}

export class AIService {
  private apiKey: string

  constructor() {
    this.apiKey = process.env.NVIDIA_API_KEY || ""
  }

  async analyze(request: AIAnalysisRequest): Promise<AIAnalysisResult> {
    if (!this.apiKey) {
      throw new Error("NVIDIA API key is not configured")
    }

    const businessSummary = this.createBusinessSummary(request.businessData)

    const systemPrompt = `You are Ledmi — an intelligent AI inventory assistant built into LedgerMind, an enterprise inventory management platform.

PERSONALITY:
- You are highly professional, analytical, and direct.
- You provide concise, data-backed insights. Do not use conversational filler, greetings, or emojis.
- Never start responses with "Analyzing data..." or "Processing request...".
- When you lack sufficient data, plainly state the missing variables.
- Keep responses strictly informative and professional.

CAPABILITIES:
- You know everything about the user's inventory, stock levels, sales history, and product performance (data provided below).
- You can spot trends, identify low-stock items, suggest restocking priorities, and analyze what's selling well vs. poorly.
- You can give business advice, help with pricing decisions, and flag potential issues before they become problems.
- You understand seasonal patterns, profit margins, and supply chain basics.

IMPORTANT RULES:
1. ALWAYS base analysis on the actual data provided below — never make up numbers or fake data.
2. When the data shows something interesting (like a product running low or a sales spike), proactively mention it.
3. Format responses in a readable way — use line breaks, bullet points, or bold text when it helps readability.
4. If someone asks about something outside your scope (like weather, coding, etc.), politely redirect them to inventory/business topics.
5. Remember context from the conversation — if someone asks a follow-up, relate it to what you just discussed.

THE USER'S CURRENT BUSINESS DATA:
${businessSummary}

Remember: You are Ledmi. Be professional, analytical, and direct. Respond in plain text — no JSON formatting, no code blocks. Wait before calling a tool to ask clarifying questions if important details (like price or category) are missing.`

    const messages: Array<any> = [
      { role: "system", content: systemPrompt },
    ]

    // Add conversation history for multi-turn context
    if (request.conversationHistory && request.conversationHistory.length > 0) {
      const recentHistory = request.conversationHistory.slice(-10)
      messages.push(...recentHistory)
    }

    if (request.query) {
      messages.push({ role: "user", content: request.query })
    }

    const tools = [
      {
        type: "function",
        function: {
          name: "add_inventory_item",
          description: "Add a completely new product/item to the inventory. ONLY use this if it's a new item. Ask for price and category if missing.",
          parameters: {
            type: "object",
            properties: {
              name: { type: "string", description: "Name of the new product" },
              current_stock: { type: "number", description: "Initial stock quantity" },
              unit_price: { type: "number", description: "Selling price" },
              min_stock_level: { type: "number", description: "Minimum stock alert level (default 10 if not specified)" },
              category_name: { type: "string", description: "Category name to place it in, or 'Uncategorized'" },
            },
            required: ["name", "current_stock", "unit_price"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "update_stock_quantity",
          description: "Update the stock quantity of an EXISTING item (e.g., adding more stock, manually fixing stock).",
          parameters: {
            type: "object",
            properties: {
              item_name: { type: "string", description: "The exact or partial name of the existing item" },
              quantity_change: { type: "number", description: "The amount to add (positive) or remove (negative)." },
            },
            required: ["item_name", "quantity_change"],
          },
        },
      },
    ]

    try {
      const response = await fetch(NVIDIA_API_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: NVIDIA_MODEL,
          messages,
          tools,
          temperature: 0.7,
          max_tokens: 1500,
          top_p: 0.7,
        }),
      })

      if (!response.ok) {
        const errorText = await response.text()
        console.error(`NVIDIA API error ${response.status}:`, errorText)
        throw new Error(`NVIDIA API error: ${response.status}`)
      }

      const result = await response.json()
      const message = result.choices?.[0]?.message

      if (!message) {
        throw new Error("Empty response from NVIDIA API")
      }

      if (message.tool_calls && message.tool_calls.length > 0) {
        return {
          toolCalls: message.tool_calls,
          assistantMessage: message,
        }
      }

      return { answer: message.content?.trim() || "Done!" }
    } catch (error) {
      console.error("NVIDIA API call failed:", error)
      return {
        answer: "An error occurred while processing your request. Please try again.",
      }
    }
  }

  private createBusinessSummary(data: BusinessData): string {
    const inventoryCount = data.inventory.length
    const totalInventoryValue = data.inventory.reduce(
      (sum, item) =>
        sum +
        ((item.current_stock as number) || 0) *
          ((item.unit_price as number) || 0),
      0
    )
    const lowStockItems = data.inventory.filter(
      (item) =>
        (item.current_stock as number) <=
        ((item.min_stock_level as number) || 10)
    )
    const totalCostValue = data.inventory.reduce(
      (sum, item) =>
        sum +
        ((item.current_stock as number) || 0) *
          ((item.cost_price as number) || 0),
      0
    )
    const zeroStockItems = data.inventory.filter((i) => (i.current_stock as number) === 0)

    const recentSales = data.sales.slice(0, 30)
    const totalRevenue = recentSales.reduce(
      (sum, sale) => sum + ((sale.total_amount as number) || 0),
      0
    )
    const avgOrderValue =
      recentSales.length > 0 ? totalRevenue / recentSales.length : 0

    const topProducts = this.getTopProducts(data.sales, data.inventory)
    const categoryBreakdown = this.getCategoryBreakdown(data.inventory, data.categories)

    const lines = [
      `INVENTORY: ${inventoryCount} products, $${totalInventoryValue.toLocaleString()} total value (cost: $${totalCostValue.toLocaleString()})`,
      `LOW STOCK (${lowStockItems.length} items): ${lowStockItems.slice(0, 5).map((i) => `${i.name} (${i.current_stock} left, min: ${i.min_stock_level})`).join(", ") || "None"}`,
      `OUT OF STOCK: ${zeroStockItems.length} items${zeroStockItems.length > 0 ? ` — ${zeroStockItems.slice(0, 3).map((i) => i.name).join(", ")}` : ""}`,
      `RECENT SALES: ${recentSales.length} transactions, $${totalRevenue.toLocaleString()} revenue, avg $${avgOrderValue.toFixed(2)}/order`,
      `TOP SELLERS: ${topProducts.map((p) => `${p.name} (${p.quantity} sold, $${p.revenue.toLocaleString()})`).join("; ") || "No sales data yet"}`,
      `CATEGORIES: ${categoryBreakdown.map((c) => `${c.name} (${c.items} items, $${c.value.toLocaleString()})`).join("; ") || "None set up"}`,
    ]

    // Add all item details for specific queries
    if (data.inventory.length > 0) {
      lines.push(`\nALL PRODUCTS:`)
      data.inventory.forEach((i) => {
        lines.push(`• ${i.name} — Stock: ${i.current_stock}, Price: $${i.unit_price}, Cost: $${i.cost_price || "N/A"}, Min Level: ${i.min_stock_level || "not set"}, SKU: ${i.sku || "N/A"}`)
      })
    }

    return lines.join("\n")
  }

  private getTopProducts(
    sales: Array<Record<string, unknown>>,
    inventory: Array<Record<string, unknown>>
  ): Array<{ name: string; quantity: number; revenue: number }> {
    const productSales = new Map<string, { quantity: number; revenue: number }>()

    sales.forEach((sale) => {
      const saleItems = sale.sale_items as Array<Record<string, unknown>> | undefined
      saleItems?.forEach((item) => {
        const itemId = item.item_id as string
        const current = productSales.get(itemId) || { quantity: 0, revenue: 0 }
        productSales.set(itemId, {
          quantity: current.quantity + ((item.quantity as number) || 0),
          revenue: current.revenue + ((item.quantity as number) || 0) * ((item.unit_price as number) || 0),
        })
      })
    })

    return Array.from(productSales.entries())
      .sort(([, a], [, b]) => b.revenue - a.revenue)
      .slice(0, 5)
      .map(([itemId, stats]) => {
        const item = inventory.find((i) => i.id === itemId)
        return {
          name: (item?.name as string) || `Product ${itemId.slice(0, 8)}`,
          quantity: stats.quantity,
          revenue: stats.revenue,
        }
      })
  }

  private getCategoryBreakdown(
    inventory: Array<Record<string, unknown>>,
    categories: Array<Record<string, unknown>>
  ): Array<{ name: string; items: number; value: number }> {
    const categoryMap = new Map<string, { items: number; value: number }>()

    inventory.forEach((item) => {
      const category = categories.find((c) => c.id === item.category_id)
      const categoryName = (category?.name as string) || "Uncategorized"
      const current = categoryMap.get(categoryName) || { items: 0, value: 0 }

      categoryMap.set(categoryName, {
        items: current.items + 1,
        value: current.value + ((item.current_stock as number) || 0) * ((item.unit_price as number) || 0),
      })
    })

    return Array.from(categoryMap.entries()).map(([name, stats]) => ({
      name,
      items: stats.items,
      value: stats.value,
    }))
  }
}

export const aiService = new AIService()