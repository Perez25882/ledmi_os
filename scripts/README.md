# LedgerMind OS — Migration Runner

This folder contains a small Node.js helper to apply the ordered SQL migrations and seeds to any Postgres database (local Supabase, Supabase cloud, or self-hosted Postgres).

## Usage

1. Copy the dashboard environment template and fill in the connection string:
   ```bash
   cp ledgermindv1-main/.env.example ledgermindv1-main/.env
   ```
2. Add the `DATABASE_URL` from your Supabase project (Database > Connection string).
3. Run the migrations:
   ```bash
   cd scripts
   npm install
   npm run apply
   ```
4. Verify the schema:
   ```bash
   npm run verify
   ```

You can also pass the connection string directly:

```bash
node apply-migrations.js "postgresql://postgres:password@db.project.supabase.co:5432/postgres"
```

## How it works

- Reads every `.sql` file in `infra/supabase/migrations` in filename order.
- Tracks applied files in a `schema_migrations` table so the script is idempotent.
- Applies seed files from `infra/supabase/seed` the same way.
