require("dotenv").config({ path: "../ledgermindv1-main/.env" })

const fs = require("fs")
const path = require("path")
const { Client } = require("pg")

const DATABASE_URL =
  process.argv[2] ||
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  process.env.SUPABASE_DATABASE_URL

if (!DATABASE_URL) {
  console.error("Missing DATABASE_URL (or POSTGRES_URL / SUPABASE_DATABASE_URL)")
  process.exit(1)
}

const MIGRATIONS_DIR = path.join(__dirname, "..", "infra", "supabase", "migrations")
const SEEDS_DIR = path.join(__dirname, "..", "infra", "supabase", "seed")

async function run() {
  const client = new Client({
    connectionString: DATABASE_URL,
    ssl: { rejectUnauthorized: false },
    family: 6,
  })
  await client.connect()

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `)

    const migrationFiles = fs
      .readdirSync(MIGRATIONS_DIR)
      .filter((f) => f.endsWith(".sql"))
      .sort()

    for (const file of migrationFiles) {
      const { rows } = await client.query("SELECT 1 FROM schema_migrations WHERE filename = $1", [file])
      if (rows.length > 0) {
        console.log(`Skipping ${file} (already applied)`)
        continue
      }

      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), "utf-8")
      console.log(`Applying ${file} ...`)
      await client.query(sql)
      await client.query("INSERT INTO schema_migrations (filename) VALUES ($1)", [file])
      console.log(`Applied ${file}`)
    }

    const seedFiles = fs
      .readdirSync(SEEDS_DIR)
      .filter((f) => f.endsWith(".sql"))
      .sort()

    for (const file of seedFiles) {
      const { rows } = await client.query("SELECT 1 FROM schema_migrations WHERE filename = $1", [file])
      if (rows.length > 0) {
        console.log(`Skipping seed ${file} (already applied)`)
        continue
      }

      const sql = fs.readFileSync(path.join(SEEDS_DIR, file), "utf-8")
      console.log(`Applying seed ${file} ...`)
      await client.query(sql)
      await client.query("INSERT INTO schema_migrations (filename) VALUES ($1)", [file])
      console.log(`Applied seed ${file}`)
    }

    console.log("All migrations and seeds applied successfully.")
  } catch (error) {
    console.error("Migration failed:", error.message)
    process.exit(1)
  } finally {
    await client.end()
  }
}

run()
