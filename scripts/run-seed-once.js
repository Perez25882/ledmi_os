const { Client } = require('pg')
const fs = require('fs')
const path = require('path')

const DATABASE_URL = process.argv[2]
if (!DATABASE_URL) {
  console.error('Usage: node run-seed-once.js <DATABASE_URL>')
  process.exit(1)
}

async function run() {
  const client = new Client({
    connectionString: DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  })
  try {
    await client.connect()
    const sql = fs.readFileSync(path.join(__dirname, '..', 'infra', 'supabase', 'seed', '001_default_roles.sql'), 'utf8')
    await client.query(sql)
    console.log('Seed applied successfully.')
  } catch (err) {
    console.error('Seed failed:', err.message)
    process.exit(1)
  } finally {
    await client.end()
  }
}

run()
