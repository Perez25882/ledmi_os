/**
 * Ledmi AI — Tool Definitions Module
 *
 * This module owns the function-tool schemas that the live `/api/ledmi/chat`
 * route (backed by `lib/nvidia-ai.ts`) will use once tool-call execution is
 * wired up (see docs/LEDMI_DESIGN.md §6.1, DEPT_AI_STATUS.md §2 "Not implemented").
 *
 * The older duplicate chat/fetch/business-summary logic that previously lived
 * here was removed during consolidation — `lib/nvidia-ai.ts` is the single
 * source of truth for NVIDIA NIM chat completions. Only the tool definitions
 * and their TypeScript types are retained, since they are not duplicated
 * anywhere else and are required by the design spec.
 */

export interface AIToolCall {
  id: string
  type: "function"
  function: {
    name: string
    arguments: string
  }
}

export interface AITool {
  type: "function"
  function: {
    name: string
    description: string
    parameters: {
      type: "object"
      properties: Record<string, { type: string; description: string }>
      required: string[]
    }
  }
}

/**
 * Tools the Ledmi assistant may invoke via NVIDIA NIM function-calling.
 * Execution handlers (Postgres RPCs) are not implemented yet — see
 * DEPT_AI_STATUS.md §2. When wired up, dispatch on `function.name` and
 * pass `JSON.parse(function.arguments)` to the handler.
 */
export const LEDMI_TOOLS: AITool[] = [
  {
    type: "function",
    function: {
      name: "add_inventory_item",
      description:
        "Add a completely new product/item to the inventory. ONLY use this if it's a new item. Ask for price and category if missing.",
      parameters: {
        type: "object",
        properties: {
          name: { type: "string", description: "Name of the new product" },
          current_stock: { type: "number", description: "Initial stock quantity" },
          unit_price: { type: "number", description: "Selling price" },
          min_stock_level: {
            type: "number",
            description: "Minimum stock alert level (default 10 if not specified)",
          },
          category_name: {
            type: "string",
            description: "Category name to place it in, or 'Uncategorized'",
          },
        },
        required: ["name", "current_stock", "unit_price"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_stock_quantity",
      description:
        "Update the stock quantity of an EXISTING item (e.g., adding more stock, manually fixing stock).",
      parameters: {
        type: "object",
        properties: {
          item_name: {
            type: "string",
            description: "The exact or partial name of the existing item",
          },
          quantity_change: {
            type: "number",
            description: "The amount to add (positive) or remove (negative).",
          },
        },
        required: ["item_name", "quantity_change"],
      },
    },
  },
]
