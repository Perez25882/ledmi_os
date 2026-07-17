# Unified Retail OS - Database Architecture

This folder contains the complete database schema, security policies,functions, and connection configuration for the Unified Retail OS.

## Files

| File | Description | Order |
|------|-------------|-------|
| `01_schema.sql` | Table definitions, constraints, indexes | Run First |
| `02_rls_policies.sql` | Row Level Security policies and helper functions | Run Second |
| `03_functions_triggers.sql` | Stored procedures, triggers, business logic | Run Third |
| `04_database_connection.sql` | Connection tuning, health checks, monitoring | Run Fourth (Optional) |
| `security_architecture.md` | Security documentation and best practices | Reference |

## Quick Setup

```bash
# Using psql (replace with your actual connection string)
psql "postgresql://user:pass@host:5432/db" -f database_architecture/01_schema.sql
psql "postgresql://user:pass@host:5432/db" -f database_architecture/02_rls_policies.sql
psql "postgresql://user:pass@host:5432/db" -f database_architecture/03_functions_triggers.sql
psql "postgresql://user:pass@host:5432/db" -f database_architecture/04_database_connection.sql

# Using Supabase CLI
# supabase db push
```

## Application Connection

Backend should connect using:
- **Supabase URL**: From your project settings
- **Anon Key**: For client-side operations
- **Service Role Key**: For server-side operations (webhooks, payment processing)
- **PostgreSQL Connection String**: For direct SQL access (migrations, analytics)

## Health Check

After setup, verify with:
```sql
SELECT * FROM health_check();
```

## Security Notes

- All tables have RLS enabled (`DENY BY DEFAULT`).
- Anonymous users (`auth.uid() IS NULL`) get `false` on all permission checks.
- Financial tables (payments, invoices, sales) are append-only from the application perspective.
- Webhook secrets **must never** be stored in client-side code.
- Use `service_role` key only in server-side Edge Functions.
