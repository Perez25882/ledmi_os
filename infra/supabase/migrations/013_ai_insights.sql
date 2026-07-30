-- 013_ai_insights.sql
-- LedgerMind OS MVP — Ledmi AI insights persistence table.
--
-- Creates the ai_insights table per docs/LEDMI_DESIGN.md §6.1 with the
-- ai_insight_type / ai_insight_status enums, supporting indexes, RLS
-- policies, and an updated_at trigger. This is the persistence layer
-- for the Ledmi proactive insight pipeline (DEPT_AI_STATUS §3 gap #12).
--
-- Idempotent: enums use DO $$ IF NOT EXISTS, table/indexes/policies use
-- IF NOT EXISTS, trigger uses DROP IF EXISTS / CREATE.
-- Depends on: 001 (businesses, update_updated_at_column), 002 (branches),
--             003 (user_belongs_to_business). auth.users is Supabase built-in.


-- ============================================================
-- 1. Enums (idempotent — Postgres lacks CREATE TYPE IF NOT EXISTS)
-- ============================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_insight_type') THEN
        CREATE TYPE ai_insight_type AS ENUM ('reorder', 'anomaly', 'margin', 'brief', 'trend');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_insight_status') THEN
        CREATE TYPE ai_insight_status AS ENUM ('pending', 'actioned', 'dismissed', 'snoozed');
    END IF;
END $$;


-- ============================================================
-- 2. Table
-- ============================================================

CREATE TABLE IF NOT EXISTS ai_insights (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id      UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    branch_id        UUID REFERENCES branches(id) ON DELETE CASCADE,
    type             ai_insight_type NOT NULL,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    confidence_score NUMERIC(3, 2),
    data_hash        TEXT,
    push_eligible    BOOLEAN NOT NULL DEFAULT false,
    status           ai_insight_status NOT NULL DEFAULT 'pending',
    actor_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actioned_at      TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
-- 3. Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_ai_insights_business
    ON ai_insights(business_id);

CREATE INDEX IF NOT EXISTS idx_ai_insights_business_branch
    ON ai_insights(business_id, branch_id);

CREATE INDEX IF NOT EXISTS idx_ai_insights_business_type_created
    ON ai_insights(business_id, type, created_at DESC);

-- Partial unique index for 24h dedupe of pending insights (Task A3).
-- Note: NOW() is not IMMUTABLE so it cannot appear in an index predicate.
-- We use a plain (non-partial) unique index on the dedupe columns instead;
-- the 24h window is enforced at query/insert time by the application layer.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ai_insights_dedupe_24h
    ON ai_insights(business_id, branch_id, type, data_hash)
    WHERE status = 'pending';


-- ============================================================
-- 4. Row Level Security
-- ============================================================

ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;

-- SELECT: business members can read their own insights.
DROP POLICY IF EXISTS "ai_insights_select_members" ON ai_insights;
CREATE POLICY "ai_insights_select_members" ON ai_insights
    FOR SELECT TO authenticated
    USING (user_belongs_to_business(business_id));

-- INSERT: only the service role (cron / edge function) writes insights.
DROP POLICY IF EXISTS "ai_insights_insert_service" ON ai_insights;
CREATE POLICY "ai_insights_insert_service" ON ai_insights
    FOR INSERT TO service_role
    WITH CHECK (true);

-- UPDATE: business members can update status (action / dismiss / snooze).
DROP POLICY IF EXISTS "ai_insights_update_members" ON ai_insights;
CREATE POLICY "ai_insights_update_members" ON ai_insights
    FOR UPDATE TO authenticated
    USING (user_belongs_to_business(business_id))
    WITH CHECK (user_belongs_to_business(business_id));

-- DELETE: no policy — denied by default under RLS.


-- ============================================================
-- 5. updated_at trigger (reuses update_updated_at_column() from 001)
-- ============================================================

DROP TRIGGER IF EXISTS set_updated_at_ai_insights ON ai_insights;
CREATE TRIGGER set_updated_at_ai_insights
    BEFORE UPDATE ON ai_insights FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
