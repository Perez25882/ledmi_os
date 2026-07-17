-- 04_database_connection.sql
-- Unified Retail OS - Database Connection & Environment Setup
--
-- This file documents and sets up the database connection
-- configuration required for the application. Run after 01-03.
-- ============================================================

-- ============================================================
-- 1. Create Application DSN/Connection Users (if not using Supabase)
-- ============================================================
-- NOTE: Replace password placeholders with actual credentials.
-- Use a secrets manager (Supabase Vault, AWS Secrets Manager, etc.)

-- Read-only connection (for reporting, analytics)
-- CREATE ROLE pos_readonly WITH LOGIN PASSWORD 'REPLACE_ME';
-- GRANT CONNECT ON DATABASE pos_db TO pos_readonly;
-- GRANT US喊 ON SCHEMA public TO pos_readonly;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO pos_readonly;

-- Application backend role (for service operations, webhooks)
CREATE ROLE IF NOT EXISTS pos_backend WITH LOGIN PASSWORD 'REPLACE_ME_-_USE_SECRETS_MANAGER';
GRANT USAGE ON SCHEMA public TO pos_backend;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO pos_backend;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO pos_backend;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO pos_backend;

-- ============================================================
-- 2. Connection Pool Optimization
-- ============================================================
-- Recommended for Supabase to reduce overhead.
-- These settings should be configured in postgresql.conf or via platform controls.

-- max_connections = 200 (set in postgresql.conf for dedicated DB)
-- shared_buffers = '256MB' (set in postgresql.conf)
-- effective_cache_size = '1GB' (set in postgresql.conf)

-- Connection string template (for application config):
-- postgresql://pos_backend:PASSWORD@db.supabase.co:5432/postgres?sslmode=require

-- ============================================================
-- 3. App Environment Variables Template
-- ============================================================

-- Required for application:
--   DATABASE_URL=postgresql://... (anon-key / role specific)
--   SUPABASE_URL=https://your-project.supabase.co
--   SUPABASE_ANON_KEY=<your-anon-key>
--   SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
--
--   PAYSTACK_SECRET_KEY=<secret>
--   PAYSTACK_PUBLIC_KEY=<public>
--
-- Optional:
--   DB_MAX_CONNECTIONS=20
--   DB_IDLE_TIMEOUT=10000
--   DB_SSL_MODE=require

-- ============================================================
-- 4. Connection Health & Monitoring
-- ============================================================

-- Active connections monitoring view
CREATE OR REPLACE VIEW v_active_connections AS
SELECT
    datname AS database_name,
    pid AS connection_id,
    usename AS username,
    state,
    application_name,
    client_addr,
    backend_start,
    state_change,
    query_start,
    query
FROM pg_stat_activity
WHERE datname = current_database();

-- Slow query log helper (run periodically)
CREATE OR REPLACE FUNCTION log_slow_queries(p_min_duration_ms INT DEFAULT 500)
RETURNS TABLE(
    query_text TEXT,
    duration_ms FLOAT,
    query_start_time TIMESTAMPTZ
) AS $func$
BEGIN
    RETURN QUERY
    SELECT
        query,
        EXTRACT(EPOCH FROM (NOW() - query_start)) * 1000 AS duration_ms,
        query_start AS query_start_time
    FROM pg_stat_activity
    WHERE query_start IS NOT NULL
      AND state = 'active'
      AND usename NOT IN ('postgres', 'supabase_admin')
      AND EXTRACT(EPOCH FROM (NOW() - query_start)) * 1000 > p_min_duration_ms
    ORDER BY duration_ms DESC;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. Application-Ready Connection Test
-- ============================================================

-- Simple function the app can call to verify DB health
CREATE OR REPLACE FUNCTION health_check()
RETURNS TABLE(
    status TEXT,
    database_version TEXT,
    connection_count BIGINT,
    rls_enabled_count BIGINT
) AS $func$
BEGIN
    RETURN QUERY
    SELECT
        'healthy'::TEXT,
        version()::TEXT,
        (SELECT COUNT(*) FROM pg_stat_activity WHERE datname = current_database())::BIGINT,
        (SELECT COUNT(*) FROM pg_tables
         WHERE schemaname = 'public'
         AND EXISTS (
             SELECT 1 FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
             LEFT JOIN pg_class toast ON toast.oid = c.relfilenode
             WHERE n.nspname = 'public'
             AND c.relname = pg_tables.tablename
             AND c.relrowsecurity = true
         ))::BIGINT;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;
