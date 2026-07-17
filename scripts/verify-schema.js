require("dotenv").config({ path: "../ledgermindv1-main/.env" })

const { Client } = require("pg")

const DATABASE_URL =
  process.argv[2] ||
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  process.env.SUPABASE_DATABASE_URL

if (!DATABASE_URL) {
  console.error("Missing DATABASE_URL")
  process.exit(1)
}

const EXPECTED_TABLES = [
  "businesses",
  "branches",
  "custom_roles",
  "user_business_roles",
  "categories",
  "suppliers",
  "products",
  "inventory",
  "inventory_logs",
  "carts",
  "cart_items",
  "invoices",
  "sales",
  "sale_items",
  "payments",
  "payment_intents",
  "payment_events",
  "webhook_receipts",
  "activity_logs",
  "refunds",
  "refund_items",
  "push_subscriptions",
  "shifts",
  "schema_migrations",
]

const EXPECTED_FUNCTIONS = [
  "user_belongs_to_business",
  "user_has_permission",
  "user_is_owner",
  "seed_default_roles",
  "process_checkout_cash",
  "create_checkout_intent",
  "safe_finalize_sale",
  "process_refund",
  "open_shift",
  "close_shift",
]

async function run() {
  const client = new Client({
    connectionString: DATABASE_URL,
    ssl: { rejectUnauthorized: false },
    family: 6,
  })
  await client.connect()

  try {
    const { rows: tableRows } = await client.query(
      `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)`,
      [EXPECTED_TABLES]
    )
    const foundTables = new Set(tableRows.map((r) => r.table_name))
    const missingTables = EXPECTED_TABLES.filter((t) => !foundTables.has(t))

    const { rows: functionRows } = await client.query(
      `SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = ANY($1)`,
      [EXPECTED_FUNCTIONS]
    )
    const foundFunctions = new Set(functionRows.map((r) => r.routine_name))
    const missingFunctions = EXPECTED_FUNCTIONS.filter((f) => !foundFunctions.has(f))

    if (missingTables.length || missingFunctions.length) {
      console.error("Missing tables:", missingTables)
      console.error("Missing functions:", missingFunctions)
      process.exit(1)
    }

    console.log("Schema verification passed.")
    console.log(`Tables: ${foundTables.size}/${EXPECTED_TABLES.length}`)
    console.log(`Functions: ${foundFunctions.size}/${EXPECTED_FUNCTIONS.length}`)
  } catch (error) {
    console.error("Verification failed:", error.message)
    process.exit(1)
  } finally {
    await client.end()
  }
}

run()
